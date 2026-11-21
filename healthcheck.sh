#!/usr/bin/env bash
set -Eeuo pipefail
port="${PORT:-8080}"
command -v curl >/dev/null 2>&1 || exit 1
curl --fail --silent --show-error --max-time 3 "http://127.0.0.1:${port}/health" >/dev/null
