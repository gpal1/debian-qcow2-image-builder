#!/bin/bash
set -e

echo "[INFO] Starting OS compatibility check..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "[DEBUG] Detected OS: $PRETTY_NAME (ID=$ID, VERSION_ID=$VERSION_ID)"

    if [ "$ID" = "debian" ]; then
        if [ "$VERSION_ID" = "12" ]; then
            echo "[INFO] Compatible OS detected: Debian 12 (Bookworm)"
        elif [ "$VERSION_ID" = "11" ]; then
            echo "[INFO] Compatible OS detected: Debian 11 (Bullseye)"
        else
            echo "[ERROR] Unsupported Debian version: $VERSION_ID. This script supports only Debian 11 or 12."
            exit 1
        fi
    else
        echo "[ERROR] Unsupported OS: $ID. This script supports only Debian 11 or 12."
        exit 1
    fi
else
    echo "[ERROR] OS release information file '/etc/os-release' not found. Cannot determine OS version."
    exit 1
fi

echo "[INFO] OS compatibility check passed. Proceeding with script..."

# CONFIGURATION
IMAGE_NAME="/root/debian_bookworm.qcow2"
IMAGE_SIZE="5G"
MOUNT_DIR="/tmp/debian_chroot"
NBD_DEV="/dev/nbd0"

# Check for required utilities and install if missing
echo "[INFO] Checking for required utilities..."
REQUIRED_PKGS="qemu-utils parted debootstrap kpartx e2fsprogs qemu-system-x86 qemu-block-extra"

for pkg in $REQUIRED_PKGS; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "[INFO] Installing $pkg..."
        apt-get update && apt-get install -y $pkg
    fi
done
echo "[INFO] Step 1 completed."

# Load NBD module (check if it's already loaded first)
if ! lsmod | grep -q "^nbd "; then
    echo "[INFO] Loading NBD kernel module..."
    modprobe nbd max_part=8 || { echo "[ERROR] Failed to load NBD module. Are you running as root?"; exit 1; }
fi

# Create mount directory
mkdir -p $MOUNT_DIR

# ERROR HANDLING & CLEANUP
function cleanup {
    echo "[INFO] Cleaning up..."

    for mp in dev/pts dev proc sys .; do
        if mountpoint -q ${MOUNT_DIR}/$mp; then
            echo "[INFO] Unmounting ${MOUNT_DIR}/$mp..."
            umount ${MOUNT_DIR}/$mp
        fi
    done

    if qemu-nbd --disconnect ${NBD_DEV} 2>/dev/null; then
        echo "[INFO] ${NBD_DEV} disconnected"
    fi

    rmdir ${MOUNT_DIR} 2>/dev/null || true
}
trap cleanup ERR

# CREATE QCOW2 IMAGE
echo "[INFO] Creating QCOW2 image..."
qemu-img create -f qcow2 ${IMAGE_NAME} ${IMAGE_SIZE}
echo "[INFO] Step 2 completed."

# PARTITION AND FORMAT
echo "[INFO] Connecting image and formatting..."
qemu-nbd --connect=${NBD_DEV} ${IMAGE_NAME}
parted --script ${NBD_DEV} mklabel msdos
parted --script ${NBD_DEV} mkpart primary ext4 1MiB 100%
sleep 2
mkfs.ext4 ${NBD_DEV}p1
mount ${NBD_DEV}p1 ${MOUNT_DIR}
echo "[INFO] Step 3 completed."

# DEBOOTSTRAP DEBIAN BOOKWORM
echo "[INFO] Bootstrapping Debian Bookworm..."
debootstrap --include=libc6,dbus,systemd,libpam-systemd,iproute2,openssh-server,sudo,mdadm,fio,dbench,cryptsetup,network-manager,gnupg,vim,grub-pc,linux-image-amd64 \
  bookworm ${MOUNT_DIR} http://deb.debian.org/debian
echo "[INFO] Step 4 completed."

# CONFIGURE APT SOURCES
echo "[INFO] Configuring apt sources..."
echo "deb [arch=amd64] http://repo.xx.local/xx-debian bookworm main contrib non-free" > ${MOUNT_DIR}/etc/apt/sources.list

# CHROOT & CONFIGURATION
echo "[INFO] Entering chroot to configure system..."
mount --bind /dev ${MOUNT_DIR}/dev
mount --bind /proc ${MOUNT_DIR}/proc
mount --bind /sys ${MOUNT_DIR}/sys
mount --bind /dev/pts ${MOUNT_DIR}/dev/pts

# Create script that will run inside chroot
cat > ${MOUNT_DIR}/setup.sh <<'EOCHROOT'
#!/bin/bash
set -e

echo "[INFO] Setting hostname..."
echo "debian-vm" > /etc/hostname

echo "[INFO] Setting root password..."
echo "root:root" | chpasswd

echo "[INFO] Enabling root SSH login..."
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "[INFO] Creating /etc/fstab..."
cat > /etc/fstab <<EOF
/dev/vda1    /    ext4    defaults    0 1
EOF

echo "[INFO] Configuring GRUB for QEMU..."
cat > /etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=Debian
GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0"
GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"
GRUB_TERMINAL=console
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOF

echo "[INFO] Creating kernel image config..."
cat > /etc/kernel-img.conf <<EOF
do_symlinks = yes
relative_links = yes
do_bootloader = yes
do_bootfloppy = no
do_initrd = yes
link_in_boot = no
EOF

echo "[INFO] Updating initramfs with virtio modules..."
echo "virtio_pci" >> /etc/initramfs-tools/modules
echo "virtio_scsi" >> /etc/initramfs-tools/modules
echo "virtio_blk" >> /etc/initramfs-tools/modules
echo "virtio_net" >> /etc/initramfs-tools/modules
update-initramfs -u

echo "[INFO] Installing GRUB bootloader..."
update-grub
grub-install --force --target=i386-pc /dev/nbd0

echo "[INFO] Enabling SSH service..."
systemctl enable ssh
EOCHROOT

chmod +x ${MOUNT_DIR}/setup.sh
chroot ${MOUNT_DIR} /setup.sh
echo "[INFO] Step 5 completed."

# VALIDATION
echo "[INFO] Validating image contents..."
REQUIRED_PKGS=(libc6 dbus systemd libpam-systemd iproute2 openssh-server sudo mdadm fio dbench cryptsetup network-manager gnupg vim grub-pc linux-image-amd64)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! chroot ${MOUNT_DIR} dpkg -l | grep -qw "$pkg"; then
        MISSING_PKGS+=("$pkg")
    fi

done

if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo "[INFO] All required packages are installed."
else
    echo "[ERROR] Missing packages: ${MISSING_PKGS[*]}"
    exit 1
fi

if grep -q "^PermitRootLogin yes" "${MOUNT_DIR}/etc/ssh/sshd_config" && \
   grep -q "^PasswordAuthentication yes" "${MOUNT_DIR}/etc/ssh/sshd_config"; then
    echo "[INFO] SSH root login with password is enabled."
else
    echo "[ERROR] SSH configuration is incorrect."
    exit 1
fi

EXPECTED_SOURCE="deb [arch=amd64] http://repo.xx.local/xx-debian bookworm main contrib non-free"
if grep -Fxq "$EXPECTED_SOURCE" "${MOUNT_DIR}/etc/apt/sources.list"; then
    echo "[INFO] APT source is configured correctly."
else
    echo "[ERROR] APT source is missing or incorrect."
    exit 1
fi

if [ ! -f "${MOUNT_DIR}/boot/grub/grub.cfg" ]; then
    echo "[ERROR] GRUB configuration not found."
    exit 1
fi

rm -f ${MOUNT_DIR}/setup.sh

cleanup
echo "[INFO] Task complete."

# Manual boot instructions
echo ""
echo "[INFO] To validate by booting the image, run:"
echo "sudo qemu-system-x86_64 -enable-kvm -smp 1 -m 1024M \\
  -drive id=d0,file=${IMAGE_NAME},if=none,format=qcow2 \\
  -device virtio-blk-pci,drive=d0,scsi=off \\
  -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=net0 \\
  -nographic"
echo ""
echo "[INFO] Then connect using: ssh root@localhost -p 2222 (password: root)"
echo "[INFO] To exit QEMU console: press Ctrl+A, then X"

