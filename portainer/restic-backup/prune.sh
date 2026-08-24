#!/bin/sh
set -eu

. /usr/local/lib/restic-backup-common.sh
acquire_lock
trap release_lock EXIT INT TERM

restic forget \
  --tag portainer-host \
  --keep-daily 14 \
  --keep-weekly 8 \
  --keep-monthly 12 \
  --keep-yearly 3 \
  --prune
