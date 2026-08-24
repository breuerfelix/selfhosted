#!/bin/sh
set -eu

# The image contains tzdata and the compose file sets TZ explicitly. Keep the
# link here as well so cron uses Europe/Berlin rather than UTC.
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  printf '%s\n' "$TZ" > /etc/timezone
fi

mkdir -p "${RESTIC_CACHE_DIR:-/tmp/restic-cache}"

# Keep the scheduler in the foreground so Docker restarts the service if cron
# exits and all job output remains visible through `docker logs`.
exec crond -f -l 2 -L /dev/stdout
