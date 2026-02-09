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
pacman -Sy --needed --noconfirm arch-install-scripts qemu-user-static qemu-user-static-binfmt dosfstools util-linux e2fsprogs

systemctl restart systemd-binfmt

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

# unmount everything on the drive
umount -q $DISK* || /bin/true

# Wipe the drive
wipefs -a "$DISK"

# Create an MBR partition table
parted -s "$DISK" mklabel msdos

# Create partitions
# 1: 4gb fat32
# 2: Remainder: ext4
parted -s "$DISK" mkpart primary fat32 1MiB 4097MiB \
                  mkpart primary ext4 4097MiB 100%

partprobe  "$DISK"
sleep 1

# Theoretically we'd want to handle NVMEs here too... but like... 360 no support. yolo.
P1="${DISK}1"
P2="${DISK}2"

mkfs.fat -F32 -n XELL "$P1"
mkfs.ext4 -FL rootfs "$P2"

mkdir /mnt/xell || /bin/true
umount /mnt/xell || /bin/true
mount "$P1" /mnt/xell

mkdir /mnt/archpower || /bin/true
umount /mnt/archpower || /bin/true
mount "$P2" /mnt/archpower

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

echo "Installing base system..."
pacstrap -KMPC ~/pacman360.conf /mnt/archpower base archpower-keyring linux-xenon networkmanager vim nano less wget openssh fastfetch jwm xorg-xinit xterm xorg-server less

echo "Initializing pacman keyring..."
arch-chroot /mnt/archpower pacman-key --init

echo "Setting hostname..."
arch-chroot /mnt/archpower sh -c 'echo arch360 > /etc/hostname'

echo "Enabling Services..."
arch-chroot /mnt/archpower systemctl enable NetworkManager
arch-chroot /mnt/archpower systemctl enable systemd-timesyncd
arch-chroot /mnt/archpower systemctl enable getty@tty1.service
arch-chroot /mnt/archpower sh -c 'echo "#!/bin/sh" > /root/.xinitrc'
arch-chroot /mnt/archpower sh -c 'echo "exec jwm" > /root/.xinitrc'

echo "Setting root password..."
arch-chroot /mnt/archpower sed  -i 's/ENCRYPT_METHOD YESCRYPT/ENCRYPT_METHOD SHA256/' /etc/login.defs
arch-chroot /mnt/archpower sed  -i 's/try_first_pass nullok shadow/try_first_pass nullok shadow sha256/' /etc/pam.d/system-auth
echo "root:password" | arch-chroot /mnt/archpower chpasswd

echo "Enabling swap space..."
arch-chroot /mnt/archpower mkswap -U clear --size 4G --file /swapfile
arch-chroot /mnt/archpower sh -c 'echo "/swapfile none swap defaults 0 0" >> /etc/fstab'

echo "Creating XeLL boot files..."

# Grab PARTUUID for kernel cmdline
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$P2")

echo
echo "Root PARTUUID: $ROOT_PARTUUID"

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
echo "archpower=\"game:/vmlinuz-linux-xenon root=PARTUUID=$ROOT_PARTUUID rw console=tty0 console=ttyS0,115200n8 panic=60 coherent_pool=16M\"" >> /mnt/xell/kboot.conf

#echo "Unmounting Partitions..."
#umount -q $DISK*
#rmdir /mnt/archpower
#rmdir /mnt/xell

echo "Done!"
echo ""