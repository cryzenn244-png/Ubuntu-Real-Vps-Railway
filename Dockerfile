FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    DISPLAY=:1 \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24

# Install system packages (core desktop + utilities)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # XFCE desktop
    xfce4 xfce4-goodies xfce4-terminal \
    # VNC
    tigervnc-standalone-server tigervnc-common \
    # noVNC dependencies
    python3 python3-numpy python3-pip \
    # Networking
    net-tools iproute2 iputils-ping dnsutils \
    # System utilities
    sudo curl wget git nano vim htop procps psmisc less \
    unzip zip tar gzip xz-utils findutils grep sed gawk \
    lsof file tree build-essential openssh-client \
    ca-certificates dbus-x11 \
    # Branding/wallpaper tools
    imagemagick \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install noVNC and websockify
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify.git /opt/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Install fastfetch (optional, if available)
RUN (apt-get update && apt-get install -y fastfetch && apt-get clean) || \
    echo "fastfetch not available in repo, skipping"

# Copy project files
COPY scripts/ /opt/miracle/scripts/
COPY config/ /opt/miracle/config/
COPY assets/ /opt/miracle/assets/
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /opt/miracle/scripts/*.sh

# Health check endpoint script
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

# No USER directive — Railway runs as root-in-namespace, but desktop services
# will be started as the dynamically created user at runtime.

EXPOSE ${NOVNC_PORT}

ENTRYPOINT ["/entrypoint.sh"]
