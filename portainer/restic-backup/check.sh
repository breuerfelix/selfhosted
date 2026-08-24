#!/bin/sh
set -eu

. /usr/local/lib/restic-backup-common.sh
acquire_lock
trap release_lock EXIT INT TERM

restic check \
  --tag portainer-host \
  --read-data-subset=5%
