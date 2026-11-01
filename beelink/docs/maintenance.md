# Maintenance

Run local commands from the repository root with `export KUBECONFIG="$PWD/temp/beelink-kubeconfig"`.

## Application changes

Edit manifests under `beelink/cluster/apps/`, validate, and push reviewed changes to `main`. Flux applies merged changes automatically. `cluster/apps-sync.yaml` defines independently managed apps and their dependencies:

```bash
flux reconcile kustomization nanobot --with-source --timeout=10m
flux get kustomizations -A
kubectl get deploy,pvc -A
```

Use `papra`, `monitoring`, or `screeps-agent` for another app. To add an app, create its directory and a sync entry. Use one replica and `Recreate` for single-writer storage. Keep PV/PVC names, paths, node affinity, and numeric ownership stable. PV/PVC pruning is disabled for persistent applications; `Retain` preserves files but does not provide backups or automatic rebinding.

For data maintenance, set the app sync's `suspend: true` in Git, push, and reconcile the root. Verify suspension, scale its Deployment to zero, and wait for its pods to terminate. Suspension alone does not stop pods. For monitoring, stop dependent Screeps agents first and stop all three monitoring Deployments before restoring their data. Restore and verify while stopped, then remove suspension in Git and reconcile. Never delete a namespace to stop an app: namespace deletion also deletes PVCs.

Room Planner remains suspended. Its registry and application setup need separate work; see its [image notes](../images/room-planner/README.md).

## Secrets

Repository-root `.sops.yaml` supplies both hosts' encryption rules. `config.sops.yaml` files are fully encrypted for `secretGenerator`; Kubernetes Secret manifests encrypt `data` and `stringData`. Keep the age identity separately recoverable in secure storage.

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops beelink/cluster/apps/papra/env.sops.yaml
```

Existing files contain their recipients. New files use the root rules when commands run from the repository root. Never commit private keys, kubeconfigs, or decrypted config. Plain `kubectl kustomize` builds ciphertext; Flux decrypts before applying.

Environment Secret changes require restarting the affected Deployment after reconciliation:

```bash
flux reconcile kustomization papra --with-source --timeout=10m
kubectl -n papra rollout restart deployment/papra
kubectl -n papra rollout status deployment/papra --timeout=300s
```

For operator credentials, follow [tailscale.md](tailscale.md). Nanobot's mutable credentials and MCP settings live on its PVC; [Google Workspace OAuth](google-workspace.md) documents callback configuration.

## Monitoring and Screeps

Grafana and the Screeps agents use these internal backends; neither has LAN or Tailscale ingress:

```text
http://victoriametrics.monitoring.svc.cluster.local:8428
http://loki.monitoring.svc.cluster.local:3100
```

The agent appends `/api/v1/import` and `/loki/api/v1/push`; do not add those paths to its environment values. Public and private workers have separate Secrets and Deployments. The private worker's configured token is rejected with HTTP 401 and needs a valid private-server token:

```bash
sops beelink/cluster/apps/screeps-agent/screeps-agent-private-env.sops.yaml
flux reconcile kustomization screeps-agent --with-source --timeout=10m
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
for app in nanobot papra monitoring screeps-agent room-planner; do
  kubectl kustomize "beelink/cluster/apps/$app" > /dev/null || break
done
kubectl kustomize beelink/cluster/infrastructure/tailscale > /dev/null
kubectl kustomize shared/cluster/k3s-upgrade-plan > /dev/null
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/site.yml --syntax-check
```

Moving files within one Flux Kustomization preserves ownership. Changing owners requires the [Flux resource-move procedure](https://fluxcd.io/flux/faq/#how-can-i-safely-move-resources-from-one-dir-to-another) with pruning disabled on the old owner until adoption is verified.
