#!/bin/sh
set -eu

umask 077

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION must be set}"

export RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
export AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/tmp/restic-cache}"

mkdir -p "$RESTIC_CACHE_DIR"

LOCK_DIR=/run/restic-backup.lock

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' 'another restic operation is already running; skipping' >&2
    exit 0
  fi
}

release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
