#!/bin/sh
set -eu

mkdir -p "${RESTIC_CACHE_DIR:-/tmp/restic-cache}"

# Keep the scheduler in the foreground so Docker restarts the service if cron
# exits and all job output remains visible through `docker logs`.
exec crond -f -l 2 -L /dev/stdout
