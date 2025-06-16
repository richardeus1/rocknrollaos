#!/bin/bash
set -e

echo "[Post-Install] Starting setup..."

# Update system just in case
pacman -Sy --noconfirm

# Install required packages (greetd, snapper, gamescope, sddm, etc.)
echo "[Post-Install] Installing core packages..."
pacman -S --noconfirm --needed \
  base-devel linux-headers \
  vulkan-radeon lib32-vulkan-radeon \
  mesa lib32-mesa \
  sof-firmware \
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber \
  noto-fonts ttf-dejavu \
  xdg-desktop-portal xdg-desktop-portal-gtk \
  git wget curl flatpak \
  greetd gamescope snapper sddm

# Create 'rocknrolla' user if it doesn't exist
if ! id "rocknrolla" &>/dev/null; then
  echo "[Post-Install] Creating user 'rocknrolla'..."
  useradd -m -G wheel,audio,video,lp,storage,games -s /bin/bash rocknrolla
  echo "rocknrolla:rocknrolla" | chpasswd
fi

# Ensure 'rocknrolla' has sudo privileges
if ! grep -q '^%wheel' /etc/sudoers; then
  echo "[Post-Install] Enabling wheel group sudo access..."
  echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi

# Configure greetd autologin to gamescope-session
echo "[Post-Install] Configuring greetd autologin..."
mkdir -p /etc/greetd
cat <<EOF > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "gamescope-session"
user = "rocknrolla"
EOF

# Enable greetd and disable sddm (optional: sddm can be re-enabled manually)
systemctl enable greetd.service
systemctl disable sddm.service || true

# Setup Flatpak + apps
echo "[Post-Install] Installing Flatpak apps..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.valvesoftware.Steam
flatpak install -y flathub com.heroicgameslauncher.hgl

# Install EmuDeck (under rocknrolla user)
echo "[Post-Install] Installing EmuDeck..."
sudo -u rocknrolla bash -c 'curl -L https://www.emudeck.com/EmuDeck.sh | bash'

# Configure Snapper for Btrfs
echo "[Post-Install] Configuring Snapper..."
snapper -c root create-config /

# Auto-detect root partition device (assumes single-disk install)
SNAP_PART=$(findmnt / -o SOURCE -n)
mkdir -p /.snapshots
mount -o subvol=.snapshots "${SNAP_PART}" /.snapshots
chmod 750 /.snapshots

# Enable Snapper timeline and cleanup timers
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Install and configure grub-btrfs
echo "[Post-Install] Installing grub-btrfs..."
git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
cd /tmp/grub-btrfs
make install
systemctl start grub-btrfsd
systemctl enable grub-btrfsd

# Regenerate GRUB config
echo "[Post-Install] Updating GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

# Disable post-install service to avoid running again
echo "[Post-Install] Disabling post-install service..."
systemctl disable post-install.service

echo "[Post-Install] Setup complete!"
