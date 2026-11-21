#!/usr/bin/env bash
set -Eeuo pipefail
log() { printf '[miracle-setup] %s\n' "$*"; }
: "${USERNAME:=miracle}"; : "${WEB_USERNAME:=$USERNAME}"; : "${WEB_PASSWORD:=${PASSWORD:-}}"; : "${VNC_PASSWORD:=${PASSWORD:-}}"; : "${DATA_DIR:=/data}"
[[ -n "$WEB_PASSWORD" && -n "$VNC_PASSWORD" ]] || { log 'Missing PASSWORD/WEB_PASSWORD or VNC_PASSWORD.'; exit 1; }

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups video,audio "$USERNAME"
fi
user_home="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ -n "$user_home" && -d "$user_home" ]] || { log 'Could not resolve desktop user home directory.'; exit 1; }
install -d -o "$USERNAME" -g "$USERNAME" -m 0750 "$user_home/.vnc" "$user_home/.config/xfce4/xfconf/xfce-perchannel-xml" "$user_home/.config/xfce4/terminal" "$user_home/Desktop"

# Passwords are supplied at runtime only. VNC's classic password format effectively uses its first 8 characters;
# the longer web password is separately protected by nginx Basic Auth with bcrypt.
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > "$user_home/.vnc/passwd"
chown "$USERNAME:$USERNAME" "$user_home/.vnc/passwd"
chmod 0600 "$user_home/.vnc/passwd"

cat > "$user_home/.vnc/xstartup" <<'XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
XSTART
chown "$USERNAME:$USERNAME" "$user_home/.vnc/xstartup"
chmod 0750 "$user_home/.vnc/xstartup"

# Keep user files and XFCE preferences on the mounted volume; keep secrets outside it.
install -d -o "$USERNAME" -g "$USERNAME" -m 0750 "$DATA_DIR/home" "$DATA_DIR/desktop-config"
if [[ ! -e "$user_home/Files" ]]; then
  ln -s "$DATA_DIR/home" "$user_home/Files"
fi
if [[ ! -e "$user_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" && -f /opt/miracle/config/xfce/xfce4-desktop.xml ]]; then
  cp /opt/miracle/config/xfce/xfce4-desktop.xml "$user_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
  chown "$USERNAME:$USERNAME" "$user_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
fi
persistent_xfce="$DATA_DIR/desktop-config/xfce4"
install -d -o "$USERNAME" -g "$USERNAME" -m 0750 "$persistent_xfce"
if [[ ! -L "$user_home/.config/xfce4" ]]; then
  if [[ -z "$(find "$persistent_xfce" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    cp -a "$user_home/.config/xfce4/." "$persistent_xfce/"
  fi
  rm -rf "$user_home/.config/xfce4"
  ln -s "$persistent_xfce" "$user_home/.config/xfce4"
fi
chown "$USERNAME:$USERNAME" "$DATA_DIR/home" "$DATA_DIR/desktop-config" "$persistent_xfce"

# Install a runtime-only nginx password file; never bake secrets into the image.
printf '%s' "$WEB_PASSWORD" | htpasswd -i -B -c /etc/nginx/.htpasswd "$WEB_USERNAME" >/dev/null
chmod 0640 /etc/nginx/.htpasswd
chown root:www-data /etc/nginx/.htpasswd

install -d -m 0755 /run/miracle
# Nginx only substitutes PORT; other nginx variables must remain intact.
envsubst '${PORT}' < /opt/miracle/config/nginx.conf.template > /etc/nginx/sites-available/miracle.conf
ln -sf /etc/nginx/sites-available/miracle.conf /etc/nginx/sites-enabled/miracle.conf
nginx -t

# Ensure the user receives branded interactive shell settings without slowing non-interactive shells.
cat > "$user_home/.bashrc.miracle" <<'BASHRC'
case $- in *i*) ;; *) return ;; esac
printf '\033[1;34mMIRACLE CLOUD VM\033[0m\nUbuntu 22.04 LTS\nPowered by Miracle Cloud\n\n'
if command -v fastfetch >/dev/null 2>&1; then fastfetch
elif command -v neofetch >/dev/null 2>&1; then neofetch
else printf 'Host information: '; uname -srm; printf 'Memory: '; awk '/MemTotal/ {printf "%.1f GiB\\n", $2/1048576}' /proc/meminfo
fi
BASHRC
if ! grep -q 'bashrc.miracle' "$user_home/.bashrc" 2>/dev/null; then printf '\n[ -f ~/.bashrc.miracle ] && . ~/.bashrc.miracle\n' >> "$user_home/.bashrc"; fi
chown "$USERNAME:$USERNAME" "$user_home/.bashrc" "$user_home/.bashrc.miracle"
chmod 0644 "$user_home/.bashrc" "$user_home/.bashrc.miracle"

log "Runtime setup completed for desktop user '$USERNAME'. Secrets were not printed."
