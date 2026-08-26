#!/bin/sh
set -eu

. /usr/local/lib/restic-backup-common.sh
acquire_lock
trap release_lock EXIT INT TERM

restic forget \
  --tag portainer-host \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --keep-yearly 3 \
  --prune
