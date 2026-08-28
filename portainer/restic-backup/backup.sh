#!/bin/sh
set -eu

. /usr/local/lib/restic-backup-common.sh
acquire_lock

# These are the only containers intentionally stopped. Monitoring is not
# touched. The names match the current Portainer deployment.
STOP_ORDER='papra hindsight portainer'
START_ORDER='portainer hindsight papra'
RUNNING_FILE=/run/restic-backup.running
: > "$RUNNING_FILE"

finish() {
  rc=$?

  # Restore the pre-backup running state even when restic or a stop operation
  # fails. Containers that were already stopped are not started.
  for container in $START_ORDER; do
    if grep -Fqx "$container" "$RUNNING_FILE"; then
      if ! docker start "$container" >/dev/null; then
        printf 'failed to restart %s\n' "$container" >&2
        rc=1
      fi
    fi
  done

  rm -f "$RUNNING_FILE"
  release_lock

  if [ "$rc" -ne 0 ]; then
    printf 'restic backup failed\n' >&2
  fi
  exit "$rc"
}
trap finish EXIT INT TERM

# Fail closed if the expected containers were renamed or removed. Backing up a
# live database would otherwise create a misleadingly successful snapshot.
for container in $STOP_ORDER; do
  if ! docker inspect "$container" >/dev/null 2>&1; then
    printf 'required container is missing: %s\n' "$container" >&2
    exit 1
  fi
done

for container in $STOP_ORDER; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$container")" = true ]; then
    printf '%s\n' "$container" >> "$RUNNING_FILE"
  fi
done

while IFS= read -r container; do
  [ -n "$container" ] || continue
  printf 'stopping %s\n' "$container"
  docker stop --time=60 "$container" >/dev/null
done < "$RUNNING_FILE"

# Keep this list explicit. Do not replace it with /data or a wildcard: the
# monitoring data under /data is intentionally outside the backup scope.
restic backup \
  --tag portainer-host \
  --tag nightly \
  /data/portainer \
  /data/hermes-backup \
  /data/hindsight \
  /data/papra
