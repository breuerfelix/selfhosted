# Maintenance

Run local commands from the repository root with `export KUBECONFIG="$PWD/temp/beelink-kubeconfig"`.

## Application changes

Both clusters remain single-node. Keep scheduling unconstrained. Existing clusters need the [static PV migration](../../shared/README.md#static-pv-migration) before deploying the `hostPath` storage manifests.

Edit manifests under `beelink/cluster/apps/`, validate, and push reviewed changes to `main`. Flux applies merged changes automatically. `cluster/apps-sync.yaml` reconciles all active applications through `cluster/apps/kustomization.yaml`, after Tailscale is ready:

```bash
flux reconcile kustomization apps --with-source --timeout=15m
flux get kustomizations -A
kubectl get deploy,pvc -A
```

To add an app, create its directory and list it in `cluster/apps/kustomization.yaml`. All active apps share reconciliation, health checks, and suspension; monitoring no longer gates Screeps startup separately. Use one replica and `Recreate` for single-writer storage. Keep PV/PVC names, paths, and numeric ownership stable. Flux prunes namespaces and PV/PVC objects removed from Git. Static `hostPath` volumes use `Retain`, so their host directories survive PVC, PV, or namespace deletion; host data cleanup is manual. `Retain` does not provide backups or automatic rebinding.

For data maintenance, set `suspend: true` on the shared `apps` sync in Git, push, and reconcile the root. Verify suspension, scale the affected Deployment to zero, and wait for its pods to terminate. Suspension pauses reconciliation for all active apps but does not stop pods. For monitoring, stop dependent Screeps agents first and stop all three monitoring Deployments before restoring their data. Restore and verify while stopped, then remove suspension in Git and reconcile. Never delete a namespace to stop an app: namespace deletion also deletes PVCs.

Room Planner remains suspended. Its registry and application setup need separate work; see its [image notes](../images/room-planner/README.md).

## Consolidate existing app syncs

Run this handover once on an existing Beelink cluster **before publishing the consolidated layout to `main`**. Fresh clusters can use the new layout directly. Removing the old syncs with pruning enabled can delete their workloads, including namespaces and their PVCs. Follow the [Flux ownership-transfer procedure](https://fluxcd.io/flux/faq/#how-can-i-safely-rename-a-flux-kustomization).

Suspend the root so it cannot restore the old settings from Git. Suspend the four old app syncs and disable their pruning before removing them:

```bash
(
  set -eu
  flux suspend kustomization flux-system
  for app in nanobot papra monitoring screeps-agent; do
    flux suspend kustomization "$app"
    kubectl -n flux-system patch kustomization "$app" --type=merge \
      -p '{"spec":{"prune":false}}'
  done
  kubectl -n flux-system get kustomizations nanobot papra monitoring screeps-agent \
    -o custom-columns=NAME:.metadata.name,PRUNE:.spec.prune,SUSPENDED:.spec.suspend
)
```

Continue only after every command succeeds and all four old syncs show `PRUNE=false` and `SUSPENDED=true`. Publish the consolidated layout to `main`, then fetch it while the root is still suspended:

```bash
flux reconcile source git flux-system
flux get sources git flux-system
```

Confirm the fetched revision contains the consolidated layout before resuming the root, so it cannot reapply the old pruning settings. Resume and verify adoption:

```bash
flux resume kustomization flux-system
flux reconcile kustomization flux-system --timeout=10m
flux reconcile kustomization apps --timeout=15m
flux tree kustomization apps
flux get kustomizations -A
kubectl get deploy,pvc -A
```

Verify the old four syncs are gone, `apps` is Ready, and its tree contains all previous application resources. The deleted old syncs leave workloads running because their pruning was disabled; the new `apps` sync adopts them with pruning enabled. Keep the root suspended if preparation fails; do not publish the consolidation until the old owners are safe to remove.

## Secrets

Repository-root `.sops.yaml` supplies both hosts' encryption rules. `config.sops.yaml` files are fully encrypted for `secretGenerator`; Kubernetes Secret manifests encrypt `data` and `stringData`. Keep the age identity separately recoverable in secure storage.

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops beelink/cluster/apps/papra/env.sops.yaml
```

Existing files contain their recipients. New files use the root rules when commands run from the repository root. Never commit private keys, kubeconfigs, or decrypted config. Plain `kubectl kustomize` builds ciphertext; Flux decrypts before applying.

Environment Secret changes require restarting the affected Deployment after reconciliation:

```bash
flux reconcile kustomization apps --with-source --timeout=15m
kubectl -n papra rollout restart deployment/papra
kubectl -n papra rollout status deployment/papra --timeout=300s
```

For operator credentials, follow [tailscale.md](tailscale.md). Nanobot's mutable credentials and MCP settings live on its PVC; [Google Workspace OAuth](google-workspace.md) documents callback configuration.

### Nanobot GitHub token

Run from an interactive terminal with Python 3 and `sops` installed:

```bash
python3 beelink/scripts/configure-nanobot-gh-token.py
```

Paste the token at the hidden prompt. The script encrypts a dedicated `nanobot-github` Secret using the root SOPS rules, adds `gh-token.sops.yaml` to Nanobot's Kustomization, and wires its `GH_TOKEN` key into the container environment. Plaintext stays in memory; encryption needs only the configured public age recipient.

Review, commit, and push the three generated/updated manifests to `main`. Flux decrypts and applies them; the initial environment change triggers a rollout. Rerun the script to rotate the token, then restart Nanobot after Flux reconciles, using the environment Secret commands above with namespace and Deployment `nanobot`.

## Monitoring and Screeps

Grafana and the Screeps agents use these internal backends; neither has LAN or Tailscale ingress:

```text
http://victoriametrics.monitoring.svc.cluster.local:8428
http://loki.monitoring.svc.cluster.local:3100
```

The agent appends `/api/v1/import` and `/loki/api/v1/push`; do not add those paths to its environment values. Public and private workers have separate Secrets and Deployments. The private worker's configured token is rejected with HTTP 401 and needs a valid private-server token:

```bash
sops beelink/cluster/apps/screeps-agent/screeps-agent-private-env.sops.yaml
flux reconcile kustomization apps --with-source --timeout=15m
kubectl -n screeps-agent rollout restart deployment/screeps-agent-private
kubectl -n screeps-agent rollout status deployment/screeps-agent-private --timeout=300s
```

Set `SOPS_AGE_KEY_FILE` as above. Verify real ingestion after replacing the token; pod readiness does not validate it. Avoid dumping decrypted Secrets or raw errors containing credentials.

No host/container metrics collector or general pod-log collector is deployed. Collector-dependent dashboards show retained history. Grafana state and plugins persist on its PVC; startup plugin installation is disabled. Review compatibility when changing Loki configuration or upgrading backends.

## LAN access

ServiceLB is enabled. Each app opts in through a separate `lan.yaml`; Nanobot's [active Service](../cluster/apps/nanobot/lan.yaml) is the reference. Change names, selector, and port for another app and include it in that app's Kustomization.

Keep `externalTrafficPolicy: Cluster`, `allocateLoadBalancerNodePorts: false`, IPv4 single-stack, and the intended LAN `loadBalancerSourceRanges`. This Service adds neither TLS nor authentication. Keep the ClusterIP Service and Tailscale Ingress for private HTTPS.

Before choosing a port, inspect host listeners, other container runtimes, Kubernetes Services, and pod `hostPort` declarations. ServiceLB reserves host ports through generated DaemonSets. Check actual connectivity and source filtering; `ss` and the reported external IP alone do not prove exposure or isolation. Keep the DHCP reservation stable. Remove `lan.yaml` from the app's resources to withdraw only its LAN endpoint.

## Routine checks

Ubuntu updates, conditional reboots, Flux components, and K3s upgrades follow the [shared maintenance policy](../../shared/README.md). After updates, check readiness and application routes:

```bash
flux get kustomizations -A
flux get sources all -A
flux get helmreleases -A
kubectl get nodes,pods,pvc -A
kubectl -n system-upgrade describe plan k3s-server
ssh bee 'findmnt /data; df -h / /data; systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager'
```

For failures, inspect pod events, storage binding, directory ownership, and application health. No scheduled application backup is configured; keep consistent off-host copies and verify restores before relying on [rebuild.md](rebuild.md).

## Local validation

```bash
kubectl kustomize beelink/cluster > /dev/null
kubectl kustomize beelink/cluster/apps > /dev/null
kubectl kustomize beelink/cluster/apps/room-planner > /dev/null
kubectl kustomize beelink/cluster/infrastructure/tailscale > /dev/null
kubectl kustomize shared/cluster > /dev/null
kubectl kustomize shared/cluster/flux-system > /dev/null
kubectl kustomize shared/cluster/system-upgrade-controller > /dev/null
kubectl kustomize shared/cluster/k3s-upgrade-plan > /dev/null
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/site.yml --syntax-check
```

Moving files within one Flux Kustomization preserves ownership. Changing owners requires the [Flux resource-move procedure](https://fluxcd.io/flux/faq/#how-can-i-safely-move-resources-from-one-dir-to-another) with pruning disabled on the old owner until adoption is verified.
