#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────
# Check for root
if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Run as root"
  exit 1
fi

echo "=== 🚀 RocknRollaOS Installer ==="

# ─────────────────────────────────────────────────────────────
# Optional Wi-Fi setup
read -rp "🔌 Do you want to connect to Wi-Fi now? (y/N): " setup_wifi
if [[ "$setup_wifi" =~ ^[Yy]$ ]]; then
  echo "[Wi-Fi] Starting iwctl..."
  iwctl
  echo "[Wi-Fi] Exiting iwctl. Continuing install..."
fi

# ─────────────────────────────────────────────────────────────
# Prompt for disk
lsblk -dpno NAME,SIZE | grep -E "/dev/nvme|/dev/sd"
read -rp "Enter target disk (e.g., /dev/nvme0n1): " DISK
if [[ ! -b "$DISK" ]]; then
  echo "[ERROR] Invalid disk."
  exit 1
fi

read -rp "⚠️ This will ERASE all data on $DISK. Proceed? (y/N): " confirm
[[ "$confirm" != "y" ]] && exit 1

# ─────────────────────────────────────────────────────────────
# Partitioning (EFI + Btrfs)
echo "[Partitioning] Creating EFI (512M) + root partition..."
wipefs -af "$DISK"
parted "$DISK" -- mklabel gpt
parted "$DISK" -- mkpart ESP fat32 1MiB 513MiB
parted "$DISK" -- set 1 esp on
parted "$DISK" -- mkpart primary btrfs 513MiB 100%

EFI_PART="${DISK}p1"
ROOT_PART="${DISK}p2"

# ─────────────────────────────────────────────────────────────
# Format
echo "[Formatting] EFI and Btrfs root..."
mkfs.fat -F32 "$EFI_PART"
mkfs.btrfs -f "$ROOT_PART"

# ─────────────────────────────────────────────────────────────
# Mount and subvolumes
mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
umount /mnt

mount -o compress=zstd,subvol=@ "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ─────────────────────────────────────────────────────────────
# Install base system
echo "[Installing Base System]..."
pacstrap -K /mnt base linux linux-firmware btrfs-progs sudo nano

# fstab
genfstab -U /mnt >> /mnt/etc/fstab

# ─────────────────────────────────────────────────────────────
# Chroot and configure inside the new system
cat <<'EOF' | arch-chroot /mnt /bin/bash
set -e

# Timezone and locale
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "rocknrolla" > /etc/hostname
cat <<EOL >> /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 rocknrolla.localdomain rocknrolla
EOL

# Initramfs
mkinitcpio -P

# Password
echo "Set password for root user"
passwd

# Bootloader
pacman -S --noconfirm grub efibootmgr os-prober
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Network
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

EOF

# ─────────────────────────────────────────────────────────────
echo "[Install Complete] Unmounting..."
umount -R /mnt
echo "✅ Done! You can now reboot into RocknRollaOS!"
