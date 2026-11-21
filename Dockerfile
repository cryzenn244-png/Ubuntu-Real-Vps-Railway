
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    USER=root \
    VNC_PORT=5901 \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    xfce4 xfce4-goodies \
    tigervnc-standalone-server novnc websockify \
    dbus-x11 x11-utils x11-xserver-utils x11-apps \
    sudo xterm vim nano curl wget git ca-certificates \
    net-tools iproute2 iputils-ping procps psmisc \
    firefox xubuntu-icon-theme \
    fonts-dejavu-core fonts-liberation \
    python3 util-linux tini \
    uidmap dbus-user-session \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Docker Engine from Docker's official Ubuntu repository.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
       "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       docker-ce docker-ce-cli containerd.io \
       docker-buildx-plugin docker-compose-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /root/.vnc /run/dbus /var/lib/docker \
    && touch /root/.Xauthority \
    && chmod 700 /root/.vnc

COPY entrypoint.sh /usr/local/bin/miracle-entrypoint
RUN chmod 755 /usr/local/bin/miracle-entrypoint

EXPOSE 6080 5901

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/miracle-entrypoint"]
