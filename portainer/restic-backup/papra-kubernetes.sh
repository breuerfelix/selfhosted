#!/bin/sh
# Sourced by backup.sh. Never enable shell tracing: kubeconfig contains a token.
PAPRA_STATE_FILE=/run/restic-backup.papra-replicas

papra_kubectl() {
  kubectl --kubeconfig="${PAPRA_KUBECONFIG:-/data/restic-backup/papra.kubeconfig}" \
    --request-timeout=30s -n papra "$@"
}

papra_quiesce() {
  [ -r "${PAPRA_KUBECONFIG:-/data/restic-backup/papra.kubeconfig}" ] || {
    printf '%s\n' 'Papra Kubernetes kubeconfig is missing; refusing live backup' >&2
    return 1
  }
  docker_running=$(docker inspect -f '{{.State.Running}}' papra) || return 1
  if [ "$docker_running" = true ]; then
    printf '%s\n' 'Docker Papra is running in Kubernetes backup mode; refusing backup' >&2
    return 1
  fi
  # A live reconcile=disabled annotation makes Flux skip this Deployment,
  # including during a forced reconciliation. No other workload is suspended.
  [ ! -e "$PAPRA_STATE_FILE" ] || {
    printf '%s\n' 'Stale Papra backup state exists; inspect before retrying' >&2
    return 1
  }
  state=$(papra_kubectl get deployment papra -o 'jsonpath={.spec.replicas}{"|"}{.metadata.annotations.kustomize\.toolkit\.fluxcd\.io/reconcile}')
  case "$state" in
    '0|'|'1|') ;;
    *) printf '%s\n' 'Papra already has a reconciliation override or unexpected replica count; refusing backup' >&2; return 1;;
  esac
  printf '%s\n' "${state%|}" > "$PAPRA_STATE_FILE"
  papra_kubectl patch deployment papra --type=merge -p \
    '{"metadata":{"annotations":{"kustomize.toolkit.fluxcd.io/reconcile":"disabled"}},"spec":{"replicas":0}}' >/dev/null
  attempts=0
  while :; do
    pods=$(papra_kubectl get pods -l app=papra -o name) || return 1
    [ -n "$pods" ] || break
    attempts=$((attempts + 1))
    [ "$attempts" -lt 120 ] || { printf '%s\n' 'Papra pods did not terminate; refusing backup' >&2; return 1; }
    sleep 2
  done
  [ "$(papra_kubectl get deployment papra -o jsonpath='{.spec.replicas}')" = 0 ]
  printf '%s\n' 'Papra Kubernetes writer stopped; Flux Deployment override active'
}

papra_resume() {
  [ -f "$PAPRA_STATE_FILE" ] || return 0
  replicas=$(cat "$PAPRA_STATE_FILE")
  case "$replicas" in 0|1) ;; *) return 1;; esac
  papra_kubectl patch deployment papra --type=merge -p \
    "{\"metadata\":{\"annotations\":{\"kustomize.toolkit.fluxcd.io/reconcile\":null}},\"spec\":{\"replicas\":$replicas}}" >/dev/null || return 1
  if [ "$replicas" = 1 ]; then
    attempts=0
    until [ "$(papra_kubectl get deployment papra -o jsonpath='{.status.readyReplicas}')" = 1 ]; do
      attempts=$((attempts + 1))
      [ "$attempts" -lt 120 ] || { printf '%s\n' 'Papra did not become Ready after backup' >&2; return 1; }
      sleep 2
    done
  fi
  rm -f "$PAPRA_STATE_FILE"
  printf '%s\n' 'Papra Kubernetes state restored; Flux override removed'
}
