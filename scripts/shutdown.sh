#!/usr/bin/env bash
set -u
printf '[miracle-shutdown] stopping desktop services\n'
if command -v supervisorctl >/dev/null 2>&1; then supervisorctl -c /opt/miracle/config/supervisord.conf shutdown >/dev/null 2>&1 || true; fi
