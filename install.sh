#!/usr/bin/env bash
set -euo pipefail
DISK="/dev/sda"
ROOT_PART="${DISK}1"
HOSTNAME="dell"
USERNAME="sachs"
TIMEZONE="Europe/Berlin"
PACKAGES=(
  base base-devel bluez bluez-utils btop chromium cmake cpupower curl
  dmenu fastfetch gdb github-cli git grub
  i3-wm i3status intel-ucode inxi iwd less linux linux-firmware lm_sensors
  maim man-db man-pages openssh
  pipewire pipewire-alsa pipewire-pulse python python-pip
  ranger tailscale tcpdump tmux traceroute tree ttf-ibm-plex unzip usbutils vim wget wireplumber
  xclip xorg-server xorg-xev xorg-xinit xorg-xrandr xorg-xset
)
ask_pw() {
  local a b
  read -r -s -p "$1: " a; echo
  read -r -s -p "Confirm: " b; echo
  [[ -n $a && $a == "$b" ]] || { echo "password mismatch or empty"; exit 1; }
  REPLY=$a
}
if [[ "${1:-}" == "chroot" ]]; then
  : "${USER_PASSWORD:?}" "${ROOT_PASSWORD:?}"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  hwclock --systohc
  printf 'en_US.UTF-8 UTF-8' > /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf
  echo "${HOSTNAME}" > /etc/hostname
  printf '[Match]\nName=en* wl*\n\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-dhcp.network
  echo "KEYMAP=neoqwertz" > /etc/vconsole.conf
  mkdir -p /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "de"
    Option "XkbVariant" "neo_qwertz"
EndSection
EOF
  useradd -m -G wheel -s /bin/bash "${USERNAME}"
  printf '%s:%s\n' "${USERNAME}" "${USER_PASSWORD}" | chpasswd
  printf '%s:%s\n' root "${ROOT_PASSWORD}" | chpasswd
  echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
  chmod 0440 /etc/sudoers.d/wheel

  cat > /home/${USERNAME}/.bashrc <<'EOF'
[[ $- != *i* ]] && return

export EDITOR=vim
PS1='\u\[\033[1;38;5;81m\]@\h\[\033[0m\]: \w \[\033[1;38;5;226m\]$ \[\033[0m\]'

HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
EOF

  cat > /home/${USERNAME}/.vimrc <<'EOF'
colorscheme lunaperche
set background=dark
set expandtab
set hlsearch
set ignorecase
set incsearch
set shiftwidth=4
set tabstop=4
syntax on
EOF

  cat > /home/${USERNAME}/.gitconfig <<'EOF'
[user]
    name = Marcel Sachs
    email = sachsmarcel@proton.me
[core]
    editor = vim
[init]
    defaultBranch = master
EOF

  cat > /home/${USERNAME}/.xinitrc <<'EOF'
xset s off -dpms
exec i3
EOF

  mkdir -p /home/${USERNAME}/.config/i3status
  cat > /home/${USERNAME}/.config/i3status/config <<'EOF'
general {colors = true interval = 1}
order += "ethernet _first_"
order += "wireless _first_"
order += "cpu_temperature 0"
order += "cpu_usage"
order += "load"
order += "memory"
order += "battery 0"
order += "volume master"
order += "tztime local"

ethernet _first_ {format_up = " E: %ip (%speed) " format_down = " E: down "}
wireless _first_ {format_up = " W: %essid %ip (%quality) " format_down = " W: down "}
cpu_temperature 0 {format = " CPU %degrees °C " path = "/sys/class/hwmon/hwmon3/temp2_input" }
cpu_usage {format = " CPU: %usage "}
load {format = " load: %1min "}
memory {format = " mem: %used "}
battery 0 {
  format = " %status %percentage %remaining "
  format_down = " No battery "
  path = "/sys/class/power_supply/BAT0/uevent"
  low_threshold = 10
}
volume master {format = " ♪ %volume " format_muted = " muted (%volume) " device = "default"}
tztime local {format = " %d.%m.%Y | %H:%M:%S "}
EOF

  chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

  mkinitcpio -p linux
  grub-install --target=i386-pc "${DISK}"
  grub-mkconfig -o /boot/grub/grub.cfg
  systemctl enable bluetooth iwd sshd systemd-networkd systemd-resolved systemd-timesyncd tailscaled
  exit 0
fi
echo ">>> This will wipe ${DISK}:"
lsblk "${DISK}"
read -rp "Type 'yes sir' to confirm: " confirm
[[ "${confirm}" == "yes sir" ]] || { echo "Aborted."; exit 1; }
ask_pw "Password for $USERNAME"; USER_PASSWORD=$REPLY
ask_pw "Password for root"; ROOT_PASSWORD=$REPLY
wipefs -a "${DISK}"
parted -s "${DISK}" -- mklabel msdos mkpart primary ext4 1MiB 100% set 1 boot on
partprobe "${DISK}"
udevadm settle
mkfs.ext4 -F "${ROOT_PART}"
mount "${ROOT_PART}" /mnt
reflector --latest 10 --country Germany --sort rate --protocol https --save /etc/pacman.d/mirrorlist
pacstrap -K /mnt "${PACKAGES[@]}"
genfstab -U /mnt >> /mnt/etc/fstab
cp "$0" /mnt/root/install-arch.sh
arch-chroot /mnt /usr/bin/env \
  USER_PASSWORD="${USER_PASSWORD}" \
  ROOT_PASSWORD="${ROOT_PASSWORD}" \
  /bin/bash /root/install-arch.sh chroot
rm /mnt/root/install-arch.sh
ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
umount -R /mnt
echo ">>> Install complete. Reboot"
