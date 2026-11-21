
#!/bin/sh
# miracle-entrypoint — POSIX launcher for the Bash startup script
set -eu

if [ ! -x /bin/bash ]; then
    echo "ERROR: Bash is not installed at /bin/bash." >&2
    exit 1
fi

exec /bin/bash /usr/local/bin/entrypoint.bash "$@"
