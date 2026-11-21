# Ubuntu 22.04 XFCE desktop for Railway (AMD64).
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    MODE=railway \
    USERNAME=miracle \
    VNC_GEOMETRY=1440x900 \
    VNC_DEPTH=24 \
    PORT=8080 \
    DATA_DIR=/data

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      xfce4 xfce4-goodies xfce4-terminal thunar mousepad xfce4-taskmanager \
      tigervnc-standalone-server tigervnc-tools novnc websockify \
      nginx supervisor apache2-utils \
      dbus-x11 dbus-user-session x11-xserver-utils x11-utils xauth \
      sudo bash-completion curl wget git nano vim htop \
      iproute2 iputils-ping dnsutils net-tools procps psmisc lsof \
      unzip zip tar gzip xz-utils findutils grep sed gawk coreutils \
      file tree less openssh-client ca-certificates \
      python3 python3-pip build-essential gcc g++ make \
      fonts-dejavu fonts-noto-core adwaita-icon-theme xubuntu-icon-theme arc-theme \
      locales tzdata systemd systemd-sysv util-linux gettext-base \
    && locale-gen en_US.UTF-8 \
    && if apt-cache show fastfetch >/dev/null 2>&1; then apt-get install -y --no-install-recommends fastfetch; fi \
    && if apt-cache show neofetch >/dev/null 2>&1; then apt-get install -y --no-install-recommends neofetch; fi \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY scripts/ /opt/miracle/scripts/
COPY config/ /opt/miracle/config/
COPY assets/ /opt/miracle/assets/
COPY systemd/ /etc/systemd/system/
COPY entrypoint.sh /usr/local/sbin/miracle-entrypoint
COPY healthcheck.sh /usr/local/bin/miracle-healthcheck
COPY README.md /opt/miracle/README.md

RUN chmod 0755 /usr/local/sbin/miracle-entrypoint /usr/local/bin/miracle-healthcheck /opt/miracle/scripts/*.sh \
    && install -d -m 0755 /opt/miracle /var/log/supervisor \
    && ln -sf /opt/miracle/scripts/miraclectl.sh /usr/local/bin/miraclectl \
    && rm -f /etc/nginx/sites-enabled/default \
    && install -d /etc/systemd/system/multi-user.target.wants \
    && ln -sf ../miracle-setup.service /etc/systemd/system/multi-user.target.wants/miracle-setup.service \
    && ln -sf ../miracle-vnc.service /etc/systemd/system/multi-user.target.wants/miracle-vnc.service \
    && ln -sf ../miracle-novnc.service /etc/systemd/system/multi-user.target.wants/miracle-novnc.service \
    && ln -sf ../miracle-health.service /etc/systemd/system/multi-user.target.wants/miracle-health.service \
    && ln -sf ../miracle-nginx.service /etc/systemd/system/multi-user.target.wants/miracle-nginx.service \
    && printf '%s\n' 'MIRACLE CLOUD VM' 'Ubuntu 22.04 LTS' 'Powered by Miracle Cloud' > /etc/issue

EXPOSE 8080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/sbin/miracle-entrypoint"]
