
#!/usr/bin/env bash
set -Eeuo pipefail

: "${VNC_PASSWORD:?Set VNC_PASSWORD as a runtime secret}"

export HOME=/root
export USER=root
export VNC_PORT="${VNC_PORT:-5901}"
export NOVNC_PORT="${PORT:-6080}"
export VNC_GEOMETRY="${VNC_GEOMETRY:-1440x900}"
export VNC_DEPTH="${VNC_DEPTH:-24}"

install -d -m 700 /root/.vnc
install -d -m 755 /run/dbus /var/lib/docker
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd
unset VNC_PASSWORD

cat > /root/.vnc/xstartup <<'XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec dbus-launch --exit-with-session startxfce4
XSTART
chmod 700 /root/.vnc/xstartup

if ! pgrep -x dbus-daemon >/dev/null; then
    dbus-daemon --system --fork
fi

cleanup() {
    echo "Stopping Miracle Cloud VM services..."
    if [[ -n "${NOVNC_PID:-}" ]]; then
        kill "$NOVNC_PID" 2>/dev/null || true
    fi
    if [[ -n "${DOCKERD_PID:-}" ]]; then
        kill -TERM "$DOCKERD_PID" 2>/dev/null || true
        wait "$DOCKERD_PID" 2>/dev/null || true
    fi
    vncserver -kill :1 2>/dev/null || true
}
trap cleanup EXIT TERM INT

# Start the Docker daemon. The host must support nested Docker.
dockerd --host=unix:///var/run/docker.sock \
    --data-root=/var/lib/docker &
DOCKERD_PID=$!

for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        echo "Docker daemon exited. Check host privileges, cgroups, and storage-driver support." >&2
        exit 1
    fi
    sleep 1
done

if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon did not become ready within 30 seconds." >&2
    exit 1
fi

vncserver :1 \
    -localhost yes \
    -SecurityTypes VncAuth \
    -geometry "$VNC_GEOMETRY" \
    -depth "$VNC_DEPTH"

websockify --web=/usr/share/novnc/ \
    "0.0.0.0:${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}" &
NOVNC_PID=$!

echo "Miracle Cloud VM started."
echo "Docker daemon is ready."
echo "VNC listens on loopback port ${VNC_PORT}."
echo "noVNC listens on port ${NOVNC_PORT}."

# Keep the main process tied to the services it manages.
while kill -0 "$DOCKERD_PID" 2>/dev/null && kill -0 "$NOVNC_PID" 2>/dev/null; do
    sleep 2
done

echo "A required service exited unexpectedly." >&2
exit 1
