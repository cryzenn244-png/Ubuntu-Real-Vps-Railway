#!/usr/bin/env bash
set -Eeuo pipefail
exec supervisorctl -c /opt/miracle/config/supervisord.conf "$@"
