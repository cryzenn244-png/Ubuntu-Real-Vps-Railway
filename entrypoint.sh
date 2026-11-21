#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[miracle-entrypoint] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

export MODE="${MODE:-railway}"
export USERNAME="${USERNAME:-miracle}"
export VNC_GEOMETRY="${VNC_GEOMETRY:-1440x900}"
export VNC_DEPTH="${VNC_DEPTH:-24}"
export PORT="${PORT:-8080}"
export DATA_DIR="${DATA_DIR:-/data}"
export WEB_USERNAME="${WEB_USERNAME:-$USERNAME}"
export WEB_PASSWORD="${WEB_PASSWORD:-${PASSWORD:-}}"
export VNC_PASSWORD="${VNC_PASSWORD:-${PASSWORD:-}}"

[[ "$MODE" == railway || "$MODE" == systemd ]] || die 'MODE must be railway or systemd.'
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die 'USERNAME must be a valid Linux username (lowercase, max 32 characters).'
[[ "$WEB_USERNAME" =~ ^[a-zA-Z0-9_.@-]{1,64}$ ]] || die 'WEB_USERNAME contains unsupported characters.'
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die 'PORT must be a valid TCP port.'
[[ "$VNC_GEOMETRY" =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]] || die 'VNC_GEOMETRY must look like 1440x900.'
[[ "$VNC_DEPTH" =~ ^(16|24|32)$ ]] || die 'VNC_DEPTH must be 16, 24, or 32.'
[[ -n "$WEB_PASSWORD" ]] || die 'Set PASSWORD or WEB_PASSWORD in runtime environment variables.'
[[ ${#WEB_PASSWORD} -ge 12 ]] || die 'WEB_PASSWORD/PASSWORD must be at least 12 characters.'
[[ -n "$VNC_PASSWORD" ]] || die 'Set VNC_PASSWORD or PASSWORD in runtime environment variables.'
[[ "$VNC_PASSWORD" != *$'\n'* && "$WEB_PASSWORD" != *$'\n'* ]] || die 'Passwords must not contain newline characters.'

if [[ "$MODE" == systemd ]]; then
  # systemd EnvironmentFile syntax is not shell syntax; JSON quoting safely escapes quotes/backslashes.
  install -d -m 0755 /run/miracle
  python3 - <<'PYENV'
import json, os
keys = ('MODE','USERNAME','PASSWORD','WEB_USERNAME','WEB_PASSWORD','VNC_PASSWORD','VNC_GEOMETRY','VNC_DEPTH','PORT','DATA_DIR')
with open('/run/miracle/environment', 'w', encoding='utf-8') as f:
    for key in keys:
        if key in os.environ:
            f.write(f'{key}={json.dumps(os.environ[key])}\n')
os.chmod('/run/miracle/environment', 0o600)
PYENV
  log 'Starting genuine systemd mode. No fallback to supervisor will be attempted.'
  exec /sbin/init
fi

log 'Initializing runtime user, passwords, persistence directories, and nginx configuration.'
/opt/miracle/scripts/runtime-setup.sh
log 'Starting Railway-compatible supervisor mode (systemd is not PID 1 in this mode).'
exec /usr/bin/supervisord -n -c /opt/miracle/config/supervisord.conf
