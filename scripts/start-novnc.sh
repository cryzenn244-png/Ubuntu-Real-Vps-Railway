#!/usr/bin/env bash
set -Eeuo pipefail
: "${USERNAME:=miracle}"
exec runuser -u "$USERNAME" -- env HOME="$(getent passwd "$USERNAME" | cut -d: -f6)" \
  websockify --heartbeat 30 127.0.0.1:6081 127.0.0.1:5901
