#!/bin/bash
set -euo pipefail

# --- Environment validation ---
: "${USERNAME:?USERNAME environment variable is required}"
: "${PASSWORD:?PASSWORD environment variable is required}"
: "${VNC_PASSWORD:?VNC_PASSWORD environment variable is required}"
: "${PORT:=8080}"
: "${VNC_GEOMETRY:=1440x900}"
: "${VNC_DEPTH:=24}"
: "${DATA_DIR:=/data}"

echo "[miracle] Starting Miracle Cloud VM (Railway-compatible mode)"
echo "[miracle] User: ${USERNAME}, Port: ${PORT}, Geometry: ${VNC_GEOMETRY}"

# --- Create user if not exists ---
if ! id "${USERNAME}" &>/dev/null; then
    useradd -m -s /bin/bash "${USERNAME}"
    echo "${USERNAME}:${PASSWORD}" | chpasswd
    echo "[miracle] User ${USERNAME} created"
fi

# Grant sudo (NOPASSWD) only if explicitly allowed
if [ "${ENABLE_SUDO:-false}" = "true" ]; then
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-miracle-user
    echo "[miracle] Sudo enabled for ${USERNAME}"
fi

# --- Prepare data directory ---
mkdir -p "${DATA_DIR}/home" "${DATA_DIR}/.vnc"
chown -R "${USERNAME}:${USERNAME}" "${DATA_DIR}"

# --- Set up VNC password ---
# Use vncpasswd -f to read from stdin (avoids interactive prompt)
echo "${VNC_PASSWORD}" | vncpasswd -f > "${DATA_DIR}/.vnc/passwd"
chmod 600 "${DATA_DIR}/.vnc/passwd"
chown "${USERNAME}:${USERNAME}" "${DATA_DIR}/.vnc/passwd"

# --- Branding: wallpaper and terminal config ---
su - "${USERNAME}" -c "mkdir -p ~/.config/xfce4/terminal ~/Desktop"
cp /opt/miracle/assets/miracle-wallpaper.svg "${DATA_DIR}/home/wallpaper.svg" 2>/dev/null || true
chown -R "${USERNAME}:${USERNAME}" "${DATA_DIR}/home"

# --- Start XFCE via TigerVNC (as user) ---
# TigerVNC's vncserver starts an X session and runs the X startup script
su - "${USERNAME}" -c "vncserver :1 \
    -geometry ${VNC_GEOMETRY} \
    -depth ${VNC_DEPTH} \
    -rfbauth ${DATA_DIR}/.vnc/passwd \
    -localhost no \
    -SecurityTypes VncAuth \
    -xstartup /opt/miracle/scripts/xstartup"

echo "[miracle] VNC server started on port ${VNC_PORT}"

# --- Start noVNC/websockify in foreground ---
# Bind to 0.0.0.0 so Railway's HTTP proxy can reach it
exec /opt/websockify/run \
    --web /opt/novnc \
    "${PORT}" \
    localhost:${VNC_PORT}
