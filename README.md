# Debian QCOW Image Builder

A tool for automatically generating **Debian Bookworm** QCOW2 images for virtual machines. While optimized for Debian Bookworm, it should work with other Debian-based distributions as well.

## Overview

This repository contains a script that automates the process of creating a **Debian Bookworm** QCOW2 image. The image is pre-configured with essential packages, SSH access, and appropriate APT sources to allow for easy installation and configuration in virtualized environments.

## Supported Environment

| **OS Distribution**             | **Version** | **Codename** | **Architecture** | **Kernel Version**     | **Validation Status**    | **Notes**                                  |
|----------------------------------|-------------|--------------|------------------|------------------------|--------------------------|--------------------------------------------|
| Debian GNU/Linux                | 12          | bookworm     | x86_64           | 5.10.0-23-amd64        | Fully validated          | All tests passed                          |
| Debian GNU/Linux                | 11          | bullseye     | x86_64           | 5.10.0-33-amd64        | Fully validated          | All tests passed                          |
| Ubuntu                          | 22.04       | jammy        | x86_64           | 5.15.0-50-generic      | Expected compatible      | Under testing                             |
| Ubuntu                          | 20.04       | focal        | x86_64           | 5.4.0-91-generic       | Pending validation        | Planned testing                           |

Testing on additional platforms is ongoing. The tool is expected to work with Ubuntu 22.04+ and other Debian-based distributions.

## Requirements

The script configures these key components:
- **Core Packages**: libc6, systemd, openssh-server, sudo, and others.
- **SSH Root Access**: SSH login is enabled for the root user, with the password set to "root".
- **APT Sources**: Proper APT repository configuration is included to ensure correct package installation.
- **GRUB Configuration**: Ensures that the image is bootable in a QEMU environment.

## System Requirements

Before running the Debian QCOW2 Image Builder script, ensure your system meets the following requirements:

- **Host System**:
  - OS: Linux (Debian or Ubuntu recommended)
  - Architecture: x86_64 (64-bit)
  - Kernel: 4.15+ (for QEMU/KVM compatibility)
  - RAM: 2GB minimum (4GB+ recommended)
  - Disk Space: 10GB+ free (depending on image size)
  - QEMU: Installed (`sudo apt install qemu-kvm`)

- **Required Dependencies**:
  - Debootstrap: `sudo apt install debootstrap`
  - Git: `sudo apt install git`
  - sudo: `sudo apt install sudo`

- **Optional**:
   - **Check CPU Virtualization Support**  
     Ensure that your CPU supports hardware virtualization (Intel VT-x for Intel processors or AMD-V for AMD processors).

  - **Enable Virtualization in BIOS**  
     Make sure that the virtualization extensions (Intel VT-x or AMD-V) are enabled in your system’s BIOS/UEFI settings for KVM acceleration.


## Quick Start

- Follow these steps to quickly set up the image:

 - **Clone the Repository**
   ```bash
   git clone https://github.com/gpal1/debian-qcow2-image-builder.git
   cd debian-qcow2-image-builder

 - **Run the Script to create Debian QCOW2 image**
   To create the Debian QCOW2 image, run the following command:
     
   ```bash
       ./debian-qcow2-image-builder.sh 2>&1 | tee qcow2-debian-bookworm-build.log

 - **Initiate QEMU Virtual Machine Boot**
     The script will display the command on screen, and you are expected to run the following command to boot the image in QEMU:
     ```bash
        sudo qemu-system-x86_64 -enable-kvm -smp 1 -m 1024M \
       -drive id=d0,file=/root/debian_bookworm.qcow2,if=none,format=qcow2 \
       -device virtio-blk-pci,drive=d0,scsi=off \
       -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=net0 \
       -nographic
     
 ## Demo

[![Debian QCOW2 Demo](https://asciinema.org/a/DEaetQ3304YJpkTiQU81vlC76.png)](https://asciinema.org/a/DEaetQ3304YJpkTiQU81vlC76)

Click the image above to watch a full demo of the build and boot process.

    
## Validation

The script includes both **automatic (offline)** and **manual (online)** validation steps to ensure the generated image is correctly configured and functional.

### Offline Validation (Automated)

The script automatically verifies the following:

- **Package Installation**: Ensures essential packages like `libc6`, `systemd`, `openssh-server` are installed.
- **SSH Configuration**: Verifies root login is enabled with the password set to "root".
- **APT Sources**: Confirms the correct entry is added to `/etc/apt/sources.list`.
- **Bootloader Setup**: Ensures GRUB is installed and properly configured.

### Online Validation (Manual)

After booting the image, you can manually verify the following:

- **Boot**: The image boots into a working Debian system.
- **SSH Access**: Verify SSH access using root credentials.
- **APT Repository**: Ensure the repository is accessible and can install packages.
- **System Services**: Confirm services like `network-manager` and `systemd` are operational.

## Troubleshooting

- **Booting issues**: Ensure KVM virtualization is enabled.
- **Image not booting**: Verify KVM and CPU virtualization (VT-x/AMD-V) are enabled.
