
# Dockerfile — Ubuntu 22.04 desktop, TigerVNC, noVNC, Docker-in-Docker
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USER=root
ENV HOME=/root
ENV NOVNC_PORT=6080
ENV DOCKER_HOST=unix:///var/run/docker.sock

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    tini \
    ca-certificates \
    curl \
    wget \
    gnupg \
    lsb-release \
    dbus \
    dbus-x11 \
    xauth \
    x11-xserver-utils \
    x11-utils \
    xterm \
    xfce4 \
    xfce4-goodies \
    xubuntu-icon-theme \
    tigervnc-standalone-server \
    tigervnc-common \
    novnc \
    websockify \
    sudo \
    git \
    vim \
    nano \
    procps \
    iproute2 \
    iputils-ping \
    net-tools \
    openssl \
    tzdata \
    ca-certificates \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce \
       docker-ce-cli \
       containerd.io \
       docker-buildx-plugin \
       docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /root/.vnc \
    /var/run/dbus \
    /var/lib/docker \
    /data \
    /tmp/.X11-unix \
    && touch /root/.Xauthority \
    && chmod 1777 /tmp/.X11-unix

COPY entrypoint.sh /usr/local/bin/miracle-entrypoint

RUN sed -i 's/\r$//' /usr/local/bin/miracle-entrypoint \
    && chmod 0755 /usr/local/bin/miracle-entrypoint

EXPOSE 5901
EXPOSE 6080

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/usr/local/bin/miracle-entrypoint"]
