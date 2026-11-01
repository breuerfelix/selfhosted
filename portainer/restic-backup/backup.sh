#!/bin/sh
set -eu

. /usr/local/lib/restic-backup-common.sh

# These are the only containers intentionally stopped. Monitoring is not
# touched. The names match the current Portainer deployment.
PAPRA_RUNTIME=${PAPRA_RUNTIME:-docker}
case "$PAPRA_RUNTIME" in
  docker) ;;
  kubernetes) . /usr/local/lib/papra-kubernetes.sh;;
  *) printf '%s\n' 'PAPRA_RUNTIME must be docker or kubernetes' >&2; exit 1;;
esac
acquire_lock
if [ "$PAPRA_RUNTIME" = kubernetes ] && [ -e "$PAPRA_STATE_FILE" ]; then
  printf '%s\n' 'Stale Papra backup state exists; inspect before retrying' >&2
  release_lock
  exit 1
fi
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

  if [ "$PAPRA_RUNTIME" = kubernetes ]; then
    if ! papra_resume; then
      printf '%s\n' 'failed to restore Papra Kubernetes state' >&2
      rc=1
    fi
  fi

  rm -f "$RUNNING_FILE"
  release_lock

  if [ "$rc" -ne 0 ]; then
    printf 'restic backup failed\n' >&2
  fi
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Fail closed if the expected containers were renamed or removed. Backing up a
# live database would otherwise create a misleadingly successful snapshot.
for container in $STOP_ORDER; do
  if ! docker inspect "$container" >/dev/null 2>&1; then
    printf 'required container is missing: %s\n' "$container" >&2
    exit 1
  fi
done

if [ "$PAPRA_RUNTIME" = kubernetes ]; then
  papra_quiesce
fi

for container in $STOP_ORDER; do
  running=$(docker inspect -f '{{.State.Running}}' "$container")
  if [ "$running" = true ]; then
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
