#!/bin/bash

PASSWORD=$1
HOSTNAME=$2
USER_PASSWORD=$3

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
mkfs.btrfs -f -L root $INSTALL_DISK"p2"

mount $INSTALL_DISK"p2" /mnt

mkdir -p /mnt/boot

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount -R /mnt

mount -o subvol=@ $INSTALL_DISK"p2" /mnt

mkdir -p /mnt/{home,boot}
mount -o subvol=@home $INSTALL_DISK"p2" /mnt/home
mount $INSTALL_DISK"p1" /mnt/boot

pacstrap -K /mnt base linux linux-firmware

genfstab -U /mnt >> /mnt/etc/fstab

# CHROOT
#

ARCH_CHROOT="arch-chroot /mnt /bin/bash -c"
#arch-chroot /mnt

$ARCH_CHROOT "echo [multilib] | tee -a /etc/pacman.conf"
$ARCH_CHROOT "echo Include = /etc/pacman.d/mirrorlist | tee -a /etc/pacman.conf"
$ARCH_CHROOT "echo [options] | tee -a /etc/pacman.conf"
$ARCH_CHROOT "echo ParallelDownloads = 15 | tee -a /etc/pacman.conf"

$ARCH_CHROOT "pacman -Sy"

packages=(
    amd-ucode
    git
    mesa
    lib32-mesa
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

$ARCH_CHROOT "yes | pacman -S ${packages[*]}"

$ARCH_CHROOT "ln -sf /usr/share/zoneinfo/Europe/Prague /etc/localtime"
$ARCH_CHROOT "hwclock --systohc"

$ARCH_CHROOT "sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen"
$ARCH_CHROOT "locale-gen"

$ARCH_CHROOT "echo LANG=en_US.UTF-8 | tee /etc/locale.conf"
$ARCH_CHROOT "echo $HOSTNAME | tee /etc/hostname"

# SERVICES
#

$ARCH_CHROOT "systemctl enable NetworkManager.service"

# APP SETTINGS
#

$ARCH_CHROOT "git config --global user.name Ardn0"
$ARCH_CHROOT "git config --global user.email holomek.o@gmail.com"

$ARCH_CHROOT "touch /etc/modprobe.d/disable_modules.conf"
$ARCH_CHROOT "echo blacklist pcspkr | tee -a /etc/modprobe.d/disable_modules.conf" 
$ARCH_CHROOT "echo blacklist snd_pcsp | tee -a /etc/modprobe.d/disable_modules.conf" 
$ARCH_CHROOT "echo blacklist uvcvideo | tee -a /etc/modprobe.d/disable_modules.conf" 
$ARCH_CHROOT "echo blacklist btusb | tee -a /etc/modprobe.d/disable_modules.conf" 
$ARCH_CHROOT "echo blacklist bluetooth | tee -a /etc/modprobe.d/disable_modules.conf" 

$ARCH_CHROOT "useradd -m ondra"
$ARCH_CHROOT "echo ondra:$USER_PASSWORD | chpasswd"
$ARCH_CHROOT "usermod -a -G wheel,audio,input,storage,video,network ondra"

# FINISHING
#

$ARCH_CHROOT "echo root:$PASSWORD | chpasswd"

$ARCH_CHROOT "bootctl install"

entry_file="/boot/loader/entries/$(date +"%d-%m-%Y_%H-%M-%S")_linux.conf"

$ARCH_CHROOT "echo title Arch Linux | tee -a $entry_file"
$ARCH_CHROOT "echo linux /vmlinuz-linux | tee -a $entry_file"
$ARCH_CHROOT "echo initrd /initramfs-linux.img | tee -a $entry_file"
$ARCH_CHROOT "echo initrd /amd-ucode.img | tee -a $entry_file"
$ARCH_CHROOT "echo options root=UUID=$(blkid -s PARTUUID -o value $INSTALL_DISK"p2") rw rootfstype=btrfs rootflags=subvol=@ | tee -a $entry_file"

$ARCH_CHROOT "exit"
umount -R /mnt
reboot
