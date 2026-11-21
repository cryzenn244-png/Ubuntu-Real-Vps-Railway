
#!/usr/bin/env bash
# entrypoint.sh — Start XFCE, VNC, noVNC and Docker daemon.

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
    "$XDG_RUNTIME_DIR"

chmod 700 "$XDG_RUNTIME_DIR"

if [[ -z "${VNC_PASSWORD:-}" ]]; then
    echo "ERROR: Set the VNC_PASSWORD environment variable."
    exit 1
fi

if [[ "${#VNC_PASSWORD}" -lt 8 ]]; then
    echo "ERROR: VNC_PASSWORD must contain at least 8 characters."
    exit 1
fi

# Classic VNC authentication uses only the first eight password characters.
printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd
unset VNC_PASSWORD

cat > /root/.vnc/xstartup <<'XSTARTUP'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTARTUP

chmod 700 /root/.vnc/xstartup

cleanup() {
    echo "Stopping desktop services..."

    if [[ -n "${NOVNC_PID:-}" ]]; then
        kill "$NOVNC_PID" 2>/dev/null || true
    fi

    if [[ -n "${VNC_PID:-}" ]]; then
        kill "$VNC_PID" 2>/dev/null || true
    fi

    if [[ -n "${DOCKERD_PID:-}" ]]; then
        kill -TERM "$DOCKERD_PID" 2>/dev/null || true
        wait "$DOCKERD_PID" 2>/dev/null || true
    fi

    if [[ -n "${DBUS_PID:-}" ]]; then
        kill "$DBUS_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT
trap 'exit 0' TERM INT

# Start a system D-Bus instance if one is not already available.
if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork
fi

# Start Docker-in-Docker. VFS is slower but avoids requiring overlay2
# support from the container's underlying filesystem.
echo "Starting Docker daemon with storage driver: ${DOCKER_STORAGE_DRIVER}"

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
        echo "ERROR: Docker daemon exited. Recent log:"
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
    echo "ERROR: Docker daemon did not become ready. Recent log:"
    tail -n 100 /var/log/dockerd.log || true
    exit 1
fi

echo "Docker daemon is ready."

# Start the VNC server with password authentication.
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
        echo "ERROR: VNC server exited. Log:"
        cat /var/log/vnc.log || true
        exit 1
    fi

    if timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/${VNC_PORT}" \
        >/dev/null 2>&1; then
        vnc_ready=true
        break
    fi

    sleep 1
done

if [[ "$vnc_ready" != true ]]; then
    echo "ERROR: VNC server did not become ready. Log:"
    cat /var/log/vnc.log || true
    exit 1
fi

echo "VNC server is listening on localhost:${VNC_PORT}."

# Railway's public HTTP service must listen on its assigned PORT.
if [[ ! "$NOVNC_PORT" =~ ^[0-9]+$ ]] ||
   (( NOVNC_PORT < 1 || NOVNC_PORT > 65535 )); then
    echo "ERROR: Invalid HTTP PORT: ${NOVNC_PORT}"
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
    echo "ERROR: noVNC exited. Log:"
    cat /var/log/novnc.log || true
    exit 1
fi

echo "noVNC is listening on port ${NOVNC_PORT}."
echo "Docker, VNC and noVNC startup completed."

# Keep the container alive and detect failed services.
while true; do
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        echo "ERROR: Docker daemon stopped."
        tail -n 100 /var/log/dockerd.log || true
        exit 1
    fi

    if ! kill -0 "$VNC_PID" 2>/dev/null; then
        echo "ERROR: VNC server stopped."
        tail -n 100 /var/log/vnc.log || true
        exit 1
    fi

    if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
        echo "ERROR: noVNC stopped."
        tail -n 100 /var/log/novnc.log || true
        exit 1
    fi

    sleep 5
done
