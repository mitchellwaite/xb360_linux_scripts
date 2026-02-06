#!/bin/bash

set -euo pipefail

echo "Arch Linux installer for Xbox 360"
echo "---------------------------------"
echo ""

grep -qi '^ID=arch' /etc/os-release || {
    echo "This script must be run on Arch Linux"
    exit 1
}

# Make sure we've got the arch install scripts and the qemu usermode emulation installed
pacman -Sy --needed arch-install-scripts qemu-user-static > /dev/null

echo "Arch Linux installer for Xbox 360"

echo "Available storage devices:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk
echo

read -rp "Enter target disk (e.g. sda, nvme0n1): " DISK
DISK="/dev/$DISK"

[ -b "$DISK" ] || { echo "Invalid block device"; exit 1; }

echo "WARNING: This script will erase all data on $DISK"
read -rp "Type YES to continue: " CONFIRM
[ "$CONFIRM" = "YES" ] || exit 1

# Wipe the drive
wipefs -a "$DISK"

# Create an MBR partition table
pated -s "$DISK" mklabel msdos

# Create partitions
# 1: 4gb fat32
# 2: 8gb swap
# 3: Remainder: ext4
parted -s "$DISK" mkpart primary fat32 1MiB 4097MiB \
                  mkpart primary linux-swap 4097MiB 12289MiB \
                  mkpart primary ext4 12289MiB 100%

partprobe  "$DISK"
sleep 1

# Theoretically we'd want to handle NVMEs here too... but like... 360 no support. yolo.
P1="${DISK}1"
P2="${DISK}2"
P3="${DISK}3"

mkfs.fat -F32 -n XELL "$P1"
mkswap "$P2"
mkfs.ext4 -L rootfs "$P3"

# Grab PARTUUID for kernel cmdline
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$P3")

echo
echo "Root PARTUUID:"
echo "$ROOT_PARTUUID"

mkdir /mnt/xell
mount "$P1" /mnt/xell

mkdir /mnt/archpower
mount "$P1" /mnt/archpower

# Create a kboot config file with the following options
#
# no timeout
# speedup=1 (full speed CPU)
# 1280x720 VGA output
#
echo "#KBOOTCONFIG" > /mnt/xell/kboot.conf
echo "timeout=0" >> /mnt/xell/kboot.conf
echo "speedup=1" >> /mnt/xell/kboot.conf
echo "videomode=8" >> /mnt/xell/kboot.conf
echo "archpower=\"uda0:/vmlinuz-linux-xenon root=PARTUUID=$ROOT_PARTUUID rw console=tty0 console=ttyS0,115200n8 panic=60 coherent_pool=16M\"" >> /mnt/xell/kboot.conf

