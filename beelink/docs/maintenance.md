# Maintenance

Run local commands from the repository root with `export KUBECONFIG="$PWD/temp/beelink-kubeconfig"`.

## Application changes

Beelink is permanently single-node. Keep scheduling unconstrained and follow the [shared storage rules](../../shared/README.md#persistent-storage).

Edit manifests under `beelink/cluster/apps/`, validate, and push reviewed changes to `main`. Flux applies merged changes automatically. `cluster/apps-sync.yaml` reconciles all Kubernetes applications through `cluster/apps/kustomization.yaml`, after Tailscale is ready:

```bash
flux reconcile kustomization apps --with-source --timeout=15m
flux get kustomizations -A
kubectl get deploy,pvc -A
```

To add an app, create its directory and list it in `cluster/apps/kustomization.yaml`. All Kubernetes applications share reconciliation, health checks, and suspension. Monitoring and Screeps agents can start concurrently. Use one replica and `Recreate` for single-writer storage. Keep PV/PVC names, paths, and numeric ownership stable. Flux prunes namespaces and PV/PVC objects removed from Git. Static `hostPath` volumes use `Retain`, so their host directories survive PVC, PV, or namespace deletion; host data cleanup is manual. `Retain` does not provide backups or automatic rebinding.

For data maintenance, set `suspend: true` on the shared `apps` sync in Git, push, and reconcile the root. Verify suspension, scale the affected Deployment to zero, and wait for its pods to terminate. Suspension pauses reconciliation for all active apps but does not stop pods. For monitoring, stop dependent Screeps agents first and stop all three monitoring Deployments before restoring their data. Restore and verify while stopped, then remove suspension in Git and reconcile. Never delete a namespace to stop an app: namespace deletion also deletes PVCs.

Room Planner shares the `apps` sync and is exposed only through Tailscale. Its public image needs no pull secret; Renovate proposes updates to its pinned `latest` digest. See [Room Planner operations](room-planner.md).

## Secrets

Repository-root `.sops.yaml` supplies both hosts' encryption rules. Kubernetes Secret manifests encrypt `data` and `stringData`. Generic `config.sops.yaml` files are fully encrypted for `secretGenerator`; Hetzner's Screeps config has a specific rule encrypting only `steamKey`. Keep the age identity separately recoverable in secure storage.

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

Paste the token at the hidden prompt. The script encrypts the `nanobot-github` Secret using the root SOPS rules. Nanobot already references its `GH_TOKEN` key; the helper also checks that the manifest wiring is present. Plaintext stays in memory; encryption needs only the configured public age recipient.

Review, commit, and push changed files to `main`, reconcile `apps`, then restart Nanobot using the environment Secret commands above with namespace and Deployment `nanobot`. Updating an existing Secret does not trigger a rollout automatically.

## Monitoring and Screeps

Loki and VictoriaMetrics are internal ClusterIP Services with no LAN or Tailscale ingress. Grafana and the Screeps agents connect to them at:

```text
http://victoriametrics.monitoring.svc.cluster.local:8428
http://loki.monitoring.svc.cluster.local:3100
```

The agent appends `/api/v1/import` and `/loki/api/v1/push`; do not add those paths to its environment values. Public and private workers have separate Secrets containing only `SCREEPS_TOKEN`. Edit ordinary settings directly in `cluster/apps/screeps-agent/app.yaml`; Deployment environment changes trigger a rollout automatically. Token changes need SOPS and a restart. To rotate the private-server token:

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

For failures, inspect pod events, storage binding, directory ownership, and application health. Nightly AWS S3 backups are the accepted policy and remain tracked in [TODO.md](../../TODO.md); no scheduled application backup is configured yet. Recovery requirements are in [rebuild.md](rebuild.md).

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
