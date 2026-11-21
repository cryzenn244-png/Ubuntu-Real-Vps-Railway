
#!/bin/bash
# entrypoint.bash — start Docker, XFCE, TigerVNC and noVNC
set -Eeuo pipefail

export HOME=/root
export USER=root
export DISPLAY=:1
export XDG_RUNTIME_DIR=/tmp/runtime-root

NOVNC_PORT="${PORT:-${NOVNC_PORT:-6080}}"
VNC_DISPLAY=":1"
VNC_PORT=5901
VNC_GEOMETRY="${VNC_GEOMETRY:-1280x800}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DOCKER_STORAGE_DRIVER="${DOCKER_STORAGE_DRIVER:-vfs}"

mkdir -p \
    /root/.vnc \
    /var/run/dbus \
    /var/lib/docker \
    /data \
    "$XDG_RUNTIME_DIR" \
    /tmp/.X11-unix

chmod 700 "$XDG_RUNTIME_DIR"

if [[ -z "${VNC_PASSWORD:-}" ]]; then
    echo "ERROR: Set the VNC_PASSWORD environment variable."
    exit 1
fi

if [[ ${#VNC_PASSWORD} -lt 8 ]]; then
    echo "ERROR: VNC_PASSWORD must contain at least 8 characters."
    exit 1
fi

# Classic VNC authentication effectively uses at most 8 password characters.
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd
unset VNC_PASSWORD

cat > /root/.vnc/xstartup <<'XSTARTUP'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTARTUP

chmod 700 /root/.vnc/xstartup

DOCKERD_PID=""
VNC_PID=""
NOVNC_PID=""

cleanup() {
    trap - EXIT TERM INT
    echo "Stopping services..."

    if [[ -n "$NOVNC_PID" ]]; then
        kill "$NOVNC_PID" 2>/dev/null || true
    fi

    if [[ -n "$VNC_PID" ]]; then
        kill "$VNC_PID" 2>/dev/null || true
    fi

    if [[ -n "$DOCKERD_PID" ]]; then
        kill -TERM "$DOCKERD_PID" 2>/dev/null || true
        wait "$DOCKERD_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'exit 0' TERM INT

# Start the system D-Bus service.
if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork
fi

# Start the nested Docker daemon.
echo "Starting Docker daemon..."

dockerd \
    --host=unix:///var/run/docker.sock \
    --storage-driver="$DOCKER_STORAGE_DRIVER" \
    --data-root=/var/lib/docker \
    --pidfile=/var/run/docker.pid \
    > /var/log/dockerd.log 2>&1 &

DOCKERD_PID=$!

docker_ready=false

for _ in $(seq 1 60); do
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        echo "ERROR: Docker daemon exited."
        tail -n 100 /var/log/dockerd.log || true
        exit 1
    fi

    if docker info >/dev/null 2>&1; then
        docker_ready=true
        break
    fi

    sleep 2
done

if [[ "$docker_ready" != true ]]; then
    echo "ERROR: Docker daemon failed to become ready."
    tail -n 100 /var/log/dockerd.log || true
    exit 1
fi

echo "Docker daemon is ready."

# Start VNC on localhost only; external access goes through noVNC.
vncserver "$VNC_DISPLAY" \
    -fg \
    -geometry "$VNC_GEOMETRY" \
    -depth "$VNC_DEPTH" \
    -localhost yes \
    -SecurityTypes VncAuth \
    > /var/log/vnc.log 2>&1 &

VNC_PID=$!

vnc_ready=false

for _ in $(seq 1 30); do
    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        echo "ERROR: VNC server exited."
        cat /var/log/vnc.log || true
        exit 1
    fi

    if timeout 1 bash -c \
        'echo >/dev/tcp/127.0.0.1/5901' >/dev/null 2>&1; then
        vnc_ready=true
        break
    fi

    sleep 1
done

if [[ "$vnc_ready" != true ]]; then
    echo "ERROR: VNC server failed to start."
    cat /var/log/vnc.log || true
    exit 1
fi

echo "VNC is listening on 127.0.0.1:${VNC_PORT}."

# Railway supplies PORT. Bind to all interfaces on that port.
if [[ ! "$NOVNC_PORT" =~ ^[0-9]+$ ]] ||
   (( NOVNC_PORT < 1 || NOVNC_PORT > 65535 )); then
    echo "ERROR: Invalid HTTP port: $NOVNC_PORT"
    exit 1
fi

websockify \
    --web=/usr/share/novnc/ \
    "0.0.0.0:${NOVNC_PORT}" \
    "127.0.0.1:${VNC_PORT}" \
    > /var/log/novnc.log 2>&1 &

NOVNC_PID=$!

sleep 2

if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    echo "ERROR: noVNC exited."
    cat /var/log/novnc.log || true
    exit 1
fi

echo "noVNC is listening on 0.0.0.0:${NOVNC_PORT}."
echo "Desktop startup completed."

while true; do
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        echo "ERROR: Docker daemon stopped."
        tail -n 100 /var/log/dockerd.log || true
        exit 1
    fi

    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        echo "ERROR: VNC server stopped."
        cat /var/log/vnc.log || true
        exit 1
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        echo "ERROR: noVNC stopped."
        cat /var/log/novnc.log || true
        exit 1
    fi

    sleep 5
done
