# Rebuild

Run local commands from the repository root. Tools: SSH, Python/uv, Ansible, kubectl, Flux, SOPS, and age. This procedure assumes a fresh Kubernetes cluster. For recovery on an existing cluster, stop affected workloads using [maintenance.md](maintenance.md) first.

## 1. Prepare the host

Use Ubuntu 24.04 with hostname `beelink` and root SSH access through alias `bee`. Keep the LAN address stable through a DHCP reservation. Retained PV node affinity targets `beelink`.

Mount the data SSD at `/data` through `/etc/fstab`. Its UUID must match `data_uuid` in `ansible/k3s.yml`. Ansible verifies the filesystem; it does not format disks, create replacement app data, or recursively change ownership. When replacing the SSD, update the expected UUID after restoring and verifying its contents.

```bash
ssh bee 'hostname; findmnt --mountpoint /data --output TARGET,SOURCE,UUID'
uv venv temp/ansible-venv
uv pip install --python temp/ansible-venv/bin/python -r shared/ansible/requirements.txt
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/site.yml
ssh bee 'k3s kubectl get nodes -o wide; systemctl show k3s -p RequiresMountsFor -p BindsTo'
```

The playbook configures the [shared maintenance policy](../../shared/README.md) and K3s. Configuration changes restart K3s. Host installation does not enable Flux applications.

## 2. Set up Kubernetes access

```bash
mkdir -p temp
(umask 077; ssh bee 'cat /etc/rancher/k3s/k3s.yaml' > temp/beelink-kubeconfig)
chmod 600 temp/beelink-kubeconfig
```

For direct LAN access, change the kubeconfig server from `https://127.0.0.1:6443` to `https://192.168.178.13:6443`. Alternatively, use `https://127.0.0.1:16443` and keep this tunnel open in another terminal:

```bash
ssh -N -L 127.0.0.1:16443:127.0.0.1:6443 bee
```

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
kubectl get nodes -o wide
```

The kubeconfig grants cluster-admin access; keep it private and out of Git. No public Kubernetes API port forwarding is needed.

## 3. Restore all persistent applications

Before enabling the root Flux sync, restore every required directory from the [storage table](../README.md), preserving numeric ownership. Restore full trees while applications are stopped. SQLite databases require consistent snapshots or copies made with their writer stopped. Verify databases and application files before continuing. For an existing data disk, verify its retained contents and ownership instead of overwriting them.

Nanobot needs its mutable `config.json`, workspace, sessions, databases, and authentication files. Papra needs its database and documents. Grafana needs its database, dashboards, plugins, and encryption settings. Loki and VictoriaMetrics need their full storage trees. Credentials on these volumes are not reconstructed from Git.

On a fresh cluster, PV/PVC objects bind by their declared names. A retained PV in `Released` state on an existing cluster needs deliberate rebinding after verifying its path and intended claim. Do not delete data to repair a binding.

No scheduled backup is configured. Rebuilding cannot recover missing application data without an independently retained copy.

## 4. Install Flux and its decryption key

Ensure the intended revision is on `main`, all required application data is ready, and the pinned images are available. Install the shared controllers first:

```bash
kubectl apply -f shared/cluster/flux-system/gotk-components.yaml
kubectl wait --for=condition=Established --timeout=120s \
  crd/gitrepositories.source.toolkit.fluxcd.io \
  crd/kustomizations.kustomize.toolkit.fluxcd.io \
  crd/helmrepositories.source.toolkit.fluxcd.io \
  crd/helmreleases.helm.toolkit.fluxcd.io
kubectl -n flux-system rollout status deployment/source-controller --timeout=180s
kubectl -n flux-system rollout status deployment/kustomize-controller --timeout=180s
kubectl -n flux-system rollout status deployment/helm-controller --timeout=180s
```

Restore the age identity from secure storage to `temp/hetzner-sops-age.key`. Its public recipient must match repository-root `.sops.yaml`:

```bash
chmod 600 temp/hetzner-sops-age.key
age-keygen -y temp/hetzner-sops-age.key
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=temp/hetzner-sops-age.key \
  --dry-run=client -o yaml | kubectl apply -f -
```

Check the [Tailscale prerequisites](tailscale.md) and committed encrypted OAuth Secret. Existing credentials can be reused if valid; replacements need encryption before deployment.

## 5. Enable reconciliation

Applying the host root sync enables every unsuspended application. All data and credentials must be ready before this command:

```bash
kubectl apply -f shared/cluster/flux-system/source.yaml -f beelink/cluster/flux-system/gotk-sync.yaml
flux reconcile kustomization flux-system --with-source --timeout=10m
flux reconcile kustomization tailscale --timeout=10m
for app in nanobot papra monitoring screeps-agent; do
  flux reconcile kustomization "$app" --timeout=15m || break
done
flux reconcile kustomization k3s-upgrade-plan --timeout=5m
```

Tailscale readiness gates Nanobot, Papra, and monitoring. Monitoring readiness gates Screeps agents. Room Planner remains suspended. The shared upgrade sync applies its Plan after root reconciliation installs the controller and CRD.

## 6. Verify

```bash
flux check
flux get kustomizations -A
flux get helmreleases -A
kubectl get nodes,pods,pvc -A
kubectl get pv
kubectl -n system-upgrade get deploy,plan,jobs
```

Open the application links in [README.md](../README.md) with Tailscale connected. Check Nanobot login and a real tool request, Papra login and downloads, Grafana dashboards/data sources, and Screeps ingestion. Verify Nanobot's LAN route separately. A Ready pod does not prove credentials work.

When downtime is convenient, perform a controlled reboot and confirm SSD mounting, node readiness, and application recovery.
