# Shared host and cluster maintenance

Hetzner and Beelink use the same Ubuntu update policy, K3s bootstrap tasks, Flux components, and K3s upgrade resources. Inventories, K3s configuration, storage checks, applications, and app sync definitions remain in each host directory. The Git source and upgrade sync are shared; repository-root `.sops.yaml` owns encryption rules for both hosts.

## Ubuntu updates

Both hosts use `Europe/Berlin` as their system timezone:

| Local time | Action |
| --- | --- |
| 01:00 | Refresh Ubuntu package lists |
| 02:00 | Install unattended package updates |
| 03:00 | Reboot if `/var/run/reboot-required` indicates one is needed, including with logged-in users |
| 04:00–05:00 | Allow K3s upgrade Jobs to start |

The shared `ubuntu_updates` role owns the complete allowed-origins list: Ubuntu release, updates, security, backports, ESM application/infrastructure security, and Docker. Each origin applies only where its repository is configured. The role does not add package repositories. Other third-party origins require an explicit change to the shared defaults. It clears inherited allowed origins and origin patterns so both hosts have the same effective policy.

APT timers have no randomized delay and do not catch up missed runs. The spring daylight-saving transition skips the 02:00 run. Updates can restart services, and a long package upgrade or reboot can extend beyond its intended window. These windows do not enforce mutual exclusion between APT and Kubernetes upgrades. Ubuntu release upgrades and Docker application image updates are not included.

From the repository root:

```bash
uv venv temp/ansible-venv
uv pip install --python temp/ansible-venv/bin/python -r shared/ansible/requirements.txt
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/site.yml --check --diff
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/site.yml --check --diff
```

Remove `--check --diff` to apply. Each host's `ubuntu-updates.yml` can also be run alone. Ansible configures systemd and unattended-upgrades; no recurring Ansible runner is required. Check mode cannot fully simulate a blank-host installation.

## K3s bootstrap and upgrades

The shared `k3s` role installs the bootstrap version only when the binary is absent. It repairs a missing service unit without replacing an existing binary, applies host-specific configuration, reloads systemd, and checks API/node readiness. Configuration changes restart K3s. The host playbooks supply the exact configuration content. Beelink supplies its SSD UUID checks, `/data` startup dependency, explicit node/network settings, swap setting, and disabled Traefik/local-storage components; ServiceLB remains enabled. Host bootstrap does not require an application's config file.

The shared server Plan tracks a single minor-version channel with concurrency one and no drain or cordon on these single-node clusters. A Job started in its window can finish later. Each cluster keeps its existing Flux owners: root `flux-system` owns the controller/CRD, and `k3s-upgrade-plan` owns the Plan and depends on root readiness. `cluster/system-upgrade-controller/plan-sync.yaml` points both clusters directly at the shared Plan directory. Root manifests must not include the Plan directly, because fresh clusters need the CRD installed first.

For a new K3s minor, review compatibility, advance one minor at a time, and update the shared Plan channel, controller kubectl helper, and Ansible bootstrap version together. Shared changes on `main` reach both clusters independently; there is no cross-cluster rollout ordering or automatic rollback.

Controller CRD and controller YAML are vendored upstream release files with pinned controller/helper images. Update the whole release together, reviewing RBAC and CRDs. Renovate's Deployment image proposal alone does not refresh the CRD or helper image in its ConfigMap. After changing that ConfigMap, reconcile and restart the controller to reload its environment:

```bash
# Select temp/hetzner-kubeconfig or temp/beelink-kubeconfig first.
flux reconcile kustomization flux-system --with-source --timeout=10m
kubectl -n system-upgrade rollout restart deployment/system-upgrade-controller
kubectl -n system-upgrade rollout status deployment/system-upgrade-controller --timeout=180s
```

Upgrade Jobs expire after their configured TTL. Inspect Plan status and events if Jobs are already gone.

## Flux components

Both clusters consume `cluster/flux-system/gotk-components.yaml` and the Git source in `cluster/flux-system/source.yaml`. Each host keeps its root sync with its own repository path and health checks. Regenerate the shared file with the intended Flux CLI version and the same three components:

```bash
flux install --export --components=source-controller,kustomize-controller,helm-controller > shared/cluster/flux-system/gotk-components.yaml
```

New-cluster bootstrap applies `shared/cluster/flux-system/gotk-components.yaml` first and waits for its CRDs and controllers. Restore data and install `flux-system/sops-age`, then apply `shared/cluster/flux-system/source.yaml` together with the host's `gotk-sync.yaml`. The source only fetches Git; the host root enables reconciliation. The Git source must retain `shared/` in its source artifact.

## Validation and routine checks

```bash
kubectl kustomize hetzner/cluster > /dev/null
kubectl kustomize beelink/cluster > /dev/null
kubectl kustomize shared/cluster/k3s-upgrade-plan > /dev/null
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/site.yml --syntax-check
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/site.yml --syntax-check
```

For each cluster, select its kubeconfig, reconcile `flux-system` with its source, then reconcile `k3s-upgrade-plan`. Check Flux readiness, nodes, pods, Helm releases, PVCs, certificates, and application routes:

```bash
flux get kustomizations -A
flux get helmreleases -A
kubectl get nodes
kubectl get pods,pvc -A
kubectl -n system-upgrade describe plan k3s-server
```

For each SSH alias (`cool` and `bee`):

```bash
ssh bee 'timedatectl show -p Timezone --value; systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager; apt-config dump'
```

A required reboot interrupts every workload on that host, including Beelink's remaining Docker apps. Verify node readiness, SSD mounting, app recovery, and other host services after the next required reboot. A healthy live check does not prove reboot recovery or a future upgrade Job.
