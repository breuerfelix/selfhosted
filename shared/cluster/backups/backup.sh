#!/bin/sh
set -eu

: "${RESTIC_HOST:?}" "${S3_BUCKET:?}" "${AWS_DEFAULT_REGION:?}" "${APPS:?}"
export RESTIC_REPOSITORY="s3:https://s3.${AWS_DEFAULT_REGION}.amazonaws.com/${S3_BUCKET}/${RESTIC_HOST}/"

# Fail before stopping any application if the repository cannot be opened.
restic cat config >/dev/null

# The Deployment currently stopped by this Job.
stopped=

resume() {
    kubectl --request-timeout=30s -n "${1%/*}" annotate deployment "${1#*/}" kustomize.toolkit.fluxcd.io/reconcile-
    kubectl --request-timeout=30s -n "${1%/*}" scale deployment "${1#*/}" --replicas=1
}

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    if [ -n "$stopped" ]; then
        resume "$stopped" || status=1
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# APPS lists one namespace/Deployment per line. Each uses app=<Deployment> Pods.
for app in $APPS; do
    namespace=${app%/*}
    deployment=${app#*/}
    [ -d "/data/$deployment" ] || {
        echo "Missing backup directory /data/$deployment" >&2
        exit 1
    }

    kubectl --request-timeout=30s -n "$namespace" annotate deployment "$deployment" \
        kustomize.toolkit.fluxcd.io/reconcile=disabled
    stopped=$app
    kubectl --request-timeout=30s -n "$namespace" scale deployment "$deployment" --replicas=0
    kubectl -n "$namespace" rollout status deployment "$deployment" --timeout=300s
    kubectl -n "$namespace" wait --for=delete pod -l "app=$deployment" --timeout=300s
    restic backup --host "$RESTIC_HOST" --tag "$deployment" "/data/$deployment"
    resume "$app"
    stopped=
    kubectl -n "$namespace" rollout status deployment "$deployment" --timeout=600s
done

restic forget --host "$RESTIC_HOST" --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
