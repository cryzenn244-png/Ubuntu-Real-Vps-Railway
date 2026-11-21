#!/usr/bin/env bash
set -Eeuo pipefail
: "${USERNAME:=miracle}"; : "${VNC_GEOMETRY:=1440x900}"; : "${VNC_DEPTH:=24}"
user_home="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ -n "$user_home" ]] || { echo '[miracle-vnc] ERROR: desktop user is missing; setup service must run first.' >&2; exit 1; }
export HOME="$user_home"
exec runuser -u "$USERNAME" -- env HOME="$user_home" USER="$USERNAME" LOGNAME="$USERNAME" \
  tigervncserver :1 -fg -localhost yes -SecurityTypes VncAuth -rfbauth "$user_home/.vnc/passwd" \
  -geometry "$VNC_GEOMETRY" -depth "$VNC_DEPTH" -xstartup "$user_home/.vnc/xstartup"
