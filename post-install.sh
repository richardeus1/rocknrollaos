#!/bin/bash
set -e

echo "[Post-Install] Starting setup..."

# Update system just in case
echo "[Post-Install] Enabling multilib repository..."
sed -i '/#\[multilib\]/,/#Include/s/^#//' /etc/pacman.conf
pacman -Sy
pacman -Sy --noconfirm

# Install required packages, including minimal KDE Plasma Desktop
echo "[Post-Install] Installing KDE Plasma and core packages..."
pacman -S --noconfirm --needed \
  base-devel linux-headers \
  plasma dolphin konsole kate systemsettings ark sddm \
  vulkan-radeon lib32-vulkan-radeon \
  mesa lib32-mesa \
  sof-firmware \
  pipewire pipewire-alsa pipewire-jack pipewire-pulse wireplumber \
  noto-fonts ttf-dejavu \
  xdg-desktop-portal xdg-desktop-portal-kde \
  git wget curl flatpak \
  greetd gamescope snapper grub-btrfs greetd-tuigreet


# Create 'rocknrolla' user if it doesn't exist
if ! id "rocknrolla" &>/dev/null; then
  echo "[Post-Install] Creating user 'rocknrolla'..."
  useradd -m -G wheel,audio,video,lp,storage,games -s /bin/bash rocknrolla
  echo "rocknrolla:rocknrolla" | chpasswd
fi

# Ensure sudo access for wheel group
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

echo "[+] Enabling NetworkManager"
systemctl enable NetworkManager

if grep -qi "z1 extreme" /proc/cpuinfo; then
    echo "[+] Detected ROG Ally — enabling greetd autologin..."
    systemctl enable greetd.service
    systemctl disable sddm.service
else
    echo "[+] VM detected — keeping SDDM as default"
    systemctl enable sddm.service
fi


# Set up Flatpak and install apps
echo "[Post-Install] Installing Flatpak apps..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.valvesoftware.Steam
flatpak install -y flathub com.heroicgameslauncher.hgl

# EmuDeck installation
#echo "[Post-Install] Installing EmuDeck..."
#sudo -u rocknrolla bash -c 'curl -L https://www.emudeck.com/EmuDeck.sh | bash'

# Install Decky Loader (Steam plugin loader)
#echo "[Post-Install] Installing Decky Loader..."
#sudo -u rocknrolla bash -c '
#  mkdir -p ~/Downloads && cd ~/Downloads
#  curl -L https://github.com/SteamDeckHomebrew/decky-loader/releases/latest/download/install_release.sh -o install_release.sh
#  chmod +x install_release.sh
#  ./install_release.sh

# Create session switcher scripts
echo "[Post-Install] Creating session switcher..."
mkdir -p /usr/local/bin

cat <<EOF > /usr/local/bin/session-switcher
#!/bin/bash
# Toggle between gamescope-session and KDE Plasma
CURRENT=\$(readlink /etc/systemd/system/default.target)
if [[ "\$CURRENT" == *gamescope-session.target ]]; then
  ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
  echo "Switched to KDE Plasma for next boot."
else
  ln -sf /usr/lib/systemd/system/gamescope-session.target /etc/systemd/system/default.target
  echo "Switched to gamescope-session for next boot."
fi
echo "Please reboot to apply."
EOF
chmod +x /usr/local/bin/session-switcher

# Ensure Desktop exists
echo "[Post-Install] Creating Desktop directory for rocknrolla..."
sudo -u rocknrolla mkdir -p /home/rocknrolla/Desktop

# Optional: create desktop shortcut for session switcher
cat <<EOF > /home/rocknrolla/Desktop/SwitchSession.desktop
[Desktop Entry]
Type=Application
Name=Switch Session
Exec=konsole -e sudo /usr/local/bin/session-switcher
Icon=system-switch-user
Terminal=false
Categories=System;
EOF
chmod +x /home/rocknrolla/Desktop/SwitchSession.desktop
chown rocknrolla:rocknrolla /home/rocknrolla/Desktop/SwitchSession.desktop

# Configure Snapper
echo "[Post-Install] Configuring Snapper..."
snapper -c root create-config /
SNAP_PART=$(findmnt / -o SOURCE -n)
mkdir -p /.snapshots
mount -o subvol=.snapshots "${SNAP_PART}" /.snapshots
chmod 750 /.snapshots

# Enable Snapper timers
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# grub-btrfs setup
echo "[Post-Install] Installing grub-btrfs..."
git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
cd /tmp/grub-btrfs
make install
systemctl start grub-btrfsd
systemctl enable grub-btrfsd

# Update GRUB
echo "[Post-Install] Updating GRUB..."
grub-mkconfig -o /boot/grub/grub.cfg

# Disable this post-install service
echo "[Post-Install] Disabling post-install service..."
systemctl disable post-install.service

echo "[Post-Install] Finished setup for RocknRollaOS!"
