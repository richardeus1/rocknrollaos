#!/bin/bash
set -e

echo "[Post-Install] Running setup tasks..."

# Create 'rocknrolla' user if it doesn't exist
if ! id "rocknrolla" &>/dev/null; then
  echo "[Post-Install] Creating user 'rocknrolla'..."
  useradd -m -G wheel -s /bin/bash rocknrolla
  echo "rocknrolla:rocknrolla" | chpasswd
fi

# Setup greetd autologin for rocknrolla
echo "[Post-Install] Configuring greetd autologin..."
mkdir -p /etc/greetd
cat <<EOF > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "gamescope-session"
user = "rocknrolla"
EOF

# Enable greetd and disable sddm (if present)
systemctl enable greetd.service
systemctl disable sddm.service || true

# Install Steam via Flatpak
echo "[Post-Install] Installing Steam (Flatpak)..."
flatpak install -y flathub com.valvesoftware.Steam

# Install Heroic Games Launcher via Flatpak
echo "[Post-Install] Installing Heroic (Flatpak)..."
flatpak install -y flathub com.heroicgameslauncher.hgl

# Download and install EmuDeck (for user rocknrolla)
echo "[Post-Install] Installing EmuDeck..."
sudo -u rocknrolla bash -c 'curl -L https://www.emudeck.com/EmuDeck.sh | bash'

# Install required packages for ROG Ally compatibility
echo "[Post-Install] Installing ROG Ally dependencies..."
pacman -S --noconfirm --needed \
  vulkan-radeon lib32-vulkan-radeon \
  mesa lib32-mesa \
  linux-headers base-devel \
  sof-firmware \
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber \
  noto-fonts ttf-dejavu \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  git wget curl

# Setup Snapper
echo "[Post-Install] Configuring Snapper and Btrfs snapshots..."
snapper -c root create-config /
mount -o subvol=.snapshots /dev/nvme0n1pX /.snapshots  # Replace with correct partition
chmod 750 /.snapshots

# Enable Snapper timeline & cleanup
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Install and configure grub-btrfs
echo "[Post-Install] Installing grub-btrfs..."
git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
cd /tmp/grub-btrfs
make install
systemctl start grub-btrfsd
systemctl enable grub-btrfsd

# Refresh GRUB config
echo "[Post-Install] Updating GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

# Disable this script from running again
echo "[Post-Install] Disabling post-install service..."
systemctl disable post-install.service

echo "[Post-Install] Done!"
