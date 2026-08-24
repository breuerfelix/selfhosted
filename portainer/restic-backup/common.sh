#!/bin/sh
set -eu

umask 077

: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY must be set}"
: "${RESTIC_PASSWORD:?RESTIC_PASSWORD must be set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"
: "${AWS_DEFAULT_REGION:?AWS_DEFAULT_REGION must be set}"

# Portainer is initially deployed with placeholders so the stack can be
# edited safely. Fail before any container is stopped until real credentials
# and a real repository are configured.
case "$RESTIC_REPOSITORY" in *REPLACE_WITH*) printf '%s\n' 'RESTIC_REPOSITORY is still a placeholder' >&2; exit 1;; esac
case "$RESTIC_PASSWORD" in *REPLACE_WITH*) printf '%s\n' 'RESTIC_PASSWORD is still a placeholder' >&2; exit 1;; esac
case "$AWS_ACCESS_KEY_ID" in *REPLACE_WITH*) printf '%s\n' 'AWS_ACCESS_KEY_ID is still a placeholder' >&2; exit 1;; esac
case "$AWS_SECRET_ACCESS_KEY" in *REPLACE_WITH*) printf '%s\n' 'AWS_SECRET_ACCESS_KEY is still a placeholder' >&2; exit 1;; esac

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
