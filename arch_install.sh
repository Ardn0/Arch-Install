#!/bin/bash

set -e # Exit if any command fail

DISK=($(ls /dev/ | grep -E 'nvme[0-9]+n[0-9]$'))
DISK_SIZE=()

for device in ${DISK[@]}; do
	size=$(lsblk -dn -o NAME,SIZE | grep "$device" | awk '{print $2}')
	echo "Found these NVME disks /dev/$device: $size"
	DISK_SIZE+=($(echo $size | cut -f1 -d"G"))
done

min_index=0

for index in "${!DISK_SIZE[@]}"; do
    if (( $(echo "${DISK_SIZE[$min_index]} > ${DISK_SIZE[$index]}" | bc -l) )); then
	min_index=$index
    fi
done

INSTALL_DISK="/dev/"${DISK[$min_index]}

# INSTALL
#

parted $INSTALL_DISK -- mklabel gpt
parted $INSTALL_DISK -- mkpart ESP fat32 1MB 512MB
parted $INSTALL_DISK -- set 1 esp on
parted $INSTALL_DISK -- mkpart root btrfs 512MB 100%

mkfs.fat -F 32 -n boot $INSTALL_DISK"p1"
mkfs.btrfs -L root $INSTALL_DISK"p2"

mkdir -p /mnt/{boot,home}
mount $INSTALL_DISK"p2" /mnt
mount $INSTALL_DISK"p1" /mnt/boot

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

mount -o subvol=@ $INSTALL_DISK"p2" /mnt
mount -o subvol=@home $INSTALL_DISK"p2" /mnt/home

pacstrap -K /mnt base linux linux-firmware

packages=(
    amd-ucode
    git
    mesa
    lib32_mesa
    xf86-video-amdgpu
    vulkan-radeon
    lib32-vulkan-radeon
    libva-mesa-driver
    lib32-libva-mesa-driver
    neovim
    htop
    lm_sensors
    pipewire
    lib32-pipewire
    networkmanager
)

for package in ${packages[@]}; do
    echo "Installing $package"
    yes | pacman -S "$package"
done

genfstab -U /mnt >> /mnt/etc/fstab

# CHROOT
#

arch-chroot /mnt
ln -sf /usr/share/zoneinfo/Europe/Prague /etc/localtime
hwclock --systohc

sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" | tee /etc/locale.conf
echo "arch_laptop" | tee /etc/hostname

# SERVICES
#

systemctl enable NetworkManager.service

# APP SETTINGS
#

git config --global user.name  "Ardn0"
git config --global user.email "holomek.o@gmail.com"

passwd

bootctl install
exit
umount -R /mnt
reboot
