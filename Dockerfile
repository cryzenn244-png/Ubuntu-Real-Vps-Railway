
# Dockerfile — Ubuntu 22.04, XFCE, VNC, noVNC, Docker and optional KVM
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    USER=root \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    DOCKER_HOST=unix:///var/run/docker.sock \
    VNC_GEOMETRY=1280x800 \
    VNC_DEPTH=24

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash tini ca-certificates curl wget gnupg \
    dbus dbus-x11 xauth x11-xserver-utils x11-utils xterm \
    xfce4 xfce4-goodies xubuntu-icon-theme \
    tigervnc-standalone-server tigervnc-common \
    novnc websockify \
    procps iproute2 iputils-ping net-tools \
    sudo git vim nano openssl tzdata \
    util-linux kmod \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /root/.vnc /var/run/dbus /var/lib/docker \
    /data /tmp/.X11-unix \
    && touch /root/.Xauthority \
    && chmod 1777 /tmp/.X11-unix

# Generate the runtime script inside the image to keep the repository
# restricted to the four requested files.
RUN cat > /usr/local/bin/miracle-entrypoint <<'ENTRYPOINT'
#!/bin/bash
set -Eeuo pipefail

export HOME=/root
export USER=root
export DISPLAY=:1
export XDG_RUNTIME_DIR=/tmp/runtime-root

HTTP_PORT="${PORT:-${NOVNC_PORT:-6080}}"
VNC_PORT="${VNC_PORT:-5901}"
GEOMETRY="${VNC_GEOMETRY:-1280x800}"
DEPTH="${VNC_DEPTH:-24}"
STORAGE_DRIVER="${DOCKER_STORAGE_DRIVER:-vfs}"

mkdir -p /root/.vnc /var/run/dbus /var/lib/docker /data "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

if [[ -z "${VNC_PASSWORD:-}" || ${#VNC_PASSWORD} -lt 8 ]]; then
    echo "ERROR: Set VNC_PASSWORD to at least 8 characters." >&2
    exit 1
fi

printf '%s\n' "$VNC_PASSWORD" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd
unset VNC_PASSWORD

cat > /root/.vnc/xstartup <<'XSTART'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XSTART
chmod 700 /root/.vnc/xstartup

if [[ ! "$HTTP_PORT" =~ ^[0-9]+$ ]] ||
   (( HTTP_PORT < 1 || HTTP_PORT > 65535 )); then
    echo "ERROR: Invalid HTTP port: $HTTP_PORT" >&2
    exit 1
fi

if ! pgrep -x dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork
fi

echo "Checking optional KVM support..."
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    echo "KVM device available."
else
    echo "KVM unavailable; hardware virtualization will not work in this container."
fi

dockerd \
    --host=unix:///var/run/docker.sock \
    --storage-driver="$STORAGE_DRIVER" \
    --data-root=/var/lib/docker \
    > /var/log/dockerd.log 2>&1 &
DOCKERD_PID=$!

VNC_PID=""
WEB_PID=""

cleanup() {
    trap - EXIT TERM INT
    [[ -n "$WEB_PID" ]] && kill "$WEB_PID" 2>/dev/null || true
    [[ -n "$VNC_PID" ]] && kill "$VNC_PID" 2>/dev/null || true
    kill -TERM "$DOCKERD_PID" 2>/dev/null || true
    wait "$DOCKERD_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

docker_ready=false
for _ in $(seq 1 60); do
    if ! kill -0 "$DOCKERD_PID" 2>/dev/null; then
        tail -n 100 /var/log/dockerd.log || true
        echo "ERROR: Docker daemon exited." >&2
        exit 1
    fi
    if docker info >/dev/null 2>&1; then
        docker_ready=true
        break
    fi
    sleep 2
done

if [[ "$docker_ready" != true ]]; then
    tail -n 100 /var/log/dockerd.log || true
    echo "ERROR: Docker daemon did not become ready." >&2
    exit 1
fi
echo "Docker daemon ready."

# Run VNC in the background. VNC remains localhost-only.
vncserver :1 \
    -geometry "$GEOMETRY" \
    -depth "$DEPTH" \
    -localhost yes \
    -SecurityTypes VncAuth
VNC_PID="$(pgrep -n Xtigervnc || true)"

if [[ -z "$VNC_PID" ]]; then
    echo "ERROR: VNC server failed to start." >&2
    exit 1
fi

websockify \
    --web=/usr/share/novnc/ \
    "0.0.0.0:${HTTP_PORT}" \
    "127.0.0.1:${VNC_PORT}" &
WEB_PID=$!

sleep 2
kill -0 "$WEB_PID" 2>/dev/null || {
    echo "ERROR: noVNC/websockify failed to start." >&2
    exit 1
}

echo "Desktop ready. noVNC port: ${HTTP_PORT}; VNC port: ${VNC_PORT}."

while true; do
    kill -0 "$DOCKERD_PID" 2>/dev/null || {
        echo "ERROR: Docker daemon stopped."
        tail -n 100 /var/log/dockerd.log || true
        exit 1
    }
    kill -0 "$VNC_PID" 2>/dev/null || {
        echo "ERROR: VNC server stopped."
        exit 1
    }
    kill -0 "$WEB_PID" 2>/dev/null || {
        echo "ERROR: noVNC stopped."
        exit 1
    }
    sleep 5
done
ENTRYPOINT

RUN chmod 0755 /usr/local/bin/miracle-entrypoint

EXPOSE 5901 6080

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/miracle-entrypoint"]
