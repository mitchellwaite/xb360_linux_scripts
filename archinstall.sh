#!/bin/bash

set -euo pipefail

clear

echo "Arch Linux installer for Xbox 360"
echo "---------------------------------"
echo ""

grep -qi '^ID=arch' /etc/os-release || {
    echo "This script must be run on Arch Linux"
    exit 1
}

# Make sure we've got the arch install scripts and the qemu usermode emulation installed
pacman -Sy --needed arch-install-scripts qemu-user-static > /dev/null

echo "Available storage devices:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk
echo

printf "Enter target disk (e.g. sda, nvme0n1): "
read RDDISK < /dev/tty
DISK="/dev/$RDDISK"

[ -b "$DISK" ] || { echo "Invalid block device"; exit 1; }

echo "WARNING: This script will erase all data on $DISK"
printf "Type YES to continue: "
read CONFIRM < /dev/tty
[ "$CONFIRM" = "YES" ] || exit 1

# Wipe the drive
wipefs -a "$DISK"

# Create an MBR partition table
parted -s "$DISK" mklabel msdos

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
echo "Root PARTUUID: $ROOT_PARTUUID"

mkdir /mnt/xell || /bin/true
umount /mnt/xell || /bin/true
mount "$P1" /mnt/xell

mkdir /mnt/archpower || /bin/true
umount /mnt/archpower || /bin/true
mount "$P1" /mnt/archpower

# Create a pacman.conf for the chroot install
cat <<EOF > ~/pacman360.conf
[options]
HoldPkg     = pacman glibc
Architecture = powerpc
Color
CheckSpace
ParallelDownloads = 5
DisableDownloadTimeout
SigLevel    = Required DatabaseOptional Never
LocalFileSigLevel = Optional
[base-any]
Server = https://repo.archlinuxpower.org/base/any
[base]
Server = https://repo.archlinuxpower.org/base/\$arch
[extra-any]
Server = https://repo.wii-linux.org/arch/extra/any
[extra]
Server = https://repo.wii-linux.org/arch/extra/\$arch
EOF

pacstrap -KMC ~/pacman360.conf /mnt/archpower base archpower-keyring linux-xenon networkmanager vim nano less wget openssh
arch-chroot /mnt/archpower "pacman-key --init"
arch-chroot /mnt/archpower pacman-key
arch-chroot /mnt/archpower "echo arch360 > /etc/hostname"
arch-chroot /mnt/archpower "systemctl enable NetworkManager"
arch-chroot /mnt/archpower "systemctl enable systemd-timesyncd"
arch-chroot /mnt/archpower "systemctl enable getty@tty1.service"
arch-chroot /mnt/archpower "sed  -i 's/ENCRYPT_METHOD YESCRYPT/ENCRYPT_METHOD SHA256/' /etc/login.defs"
arch-chroot /mnt/archpower "echo password | passwd --stdin"

cp /mnt/archpower/usr/lib/modules/*/zImage.xenon /mnt/xell/vmlinuz-linux-xenon

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

