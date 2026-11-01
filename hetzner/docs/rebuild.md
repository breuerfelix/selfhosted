# Rebuild

Run local commands from the repository root. Tools: SSH, Python/uv, kubectl, Flux, and SOPS. Use an Ubuntu 24.04 VPS with root SSH access. `ansible/inventory.ini` uses SSH alias `cool`; change the inventory or your SSH config for another host.

## 1. Prepare host access

Attach a Hetzner Cloud Firewall before starting K3s. Allow inbound TCP 80/443 publicly, TCP 22 from your administration addresses, and TCP 6443 from addresses that need Kubernetes API access. Cover IPv4 and IPv6 as appropriate. Leave outbound traffic allowed. Kubelet and Flannel ports do not need public access on one node.

Keep your existing SSH session open and verify a fresh `ssh cool` connection after changing firewall rules. Update source restrictions when your public IP changes. Verify actual rules in Hetzner Console; repository files do not configure the provider firewall.

For retained local PVs, the node hostname must match `spec.nodeAffinity` in each app's `storage.yaml`. Set the host hostname accordingly before first starting K3s, or update those manifests for the new host before bootstrap. Preserve existing node identities on an already-running cluster.

## 2. Configure Ubuntu, storage, and K3s

```bash
uv venv temp/ansible-venv
uv pip install --python temp/ansible-venv/bin/python -r shared/ansible/requirements.txt
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/site.yml
```

The playbook uses the [shared maintenance roles](../../shared/README.md), configures nightly Ubuntu updates, creates retained storage directories, installs K3s if absent, and enables/starts its service. Existing K3s binaries are left at their installed version. Changed K3s configuration restarts the service. Individual playbooks can also be run separately.

Copy the kubeconfig without making it world-readable, then replace the loopback API address with the VPS public IPv4:

```bash
mkdir -p temp
(umask 077; ssh cool 'cat /etc/rancher/k3s/k3s.yaml' > temp/hetzner-kubeconfig)
chmod 600 temp/hetzner-kubeconfig
# Edit server: https://127.0.0.1:6443 to https://<VPS_IP>:6443.
export KUBECONFIG="$PWD/temp/hetzner-kubeconfig"
kubectl get nodes -o wide
kubectl -n kube-system rollout status deployment/traefik --timeout=300s
kubectl wait --for=condition=Established --timeout=120s crd/middlewares.traefik.io crd/ingressroutes.traefik.io
```

K3s adds the host's default IPv4 to the API certificate. The kubeconfig grants cluster-admin access; keep it out of Git. `temp/` is ignored.

## 3. Restore application data

Before enabling Flux apps, restore data required by each app's recovery policy in [README.md](README.md). For a new empty installation, leave the prepared directories empty. For recovery, do not start a data-dependent app until its backup is restored.

Retained PV paths are declared in each app's `storage.yaml`. Restore the full directory tree, preserving ownership, while workloads are stopped. Ghost content uses UID:GID `1000:0`; Fathom uses `0:0`. SQLite backups must be consistent snapshots or copies made while the application was stopped. Verify restored databases and required content before proceeding. Ansible sets directory ownership but does not recursively repair restored files.

Disposable PVCs are created by K3s's local-path provisioner. Stateless apps need no restore. On a fresh cluster, new PV/PVC objects bind by their declared names. On an existing cluster, a retained PV in `Released` state may need its old claim reference cleared before reuse; first verify the path and intended claim. Do not remove data files to repair a binding.

## 4. Bootstrap Flux

Ensure the desired revision is pushed to `main`. Apply the committed Flux components and wait for their controllers:

```bash
kubectl apply -k shared/cluster/flux-system
kubectl wait --for=condition=Established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io crd/ocirepositories.source.toolkit.fluxcd.io crd/helmreleases.helm.toolkit.fluxcd.io
kubectl -n flux-system rollout status deployment/source-controller --timeout=180s
kubectl -n flux-system rollout status deployment/kustomize-controller --timeout=180s
kubectl -n flux-system rollout status deployment/helm-controller --timeout=180s
```

Restore the age identity from your password manager to `temp/hetzner-sops-age.key`, mode `0600`. Install it before enabling Git reconciliation:

```bash
chmod 600 temp/hetzner-sops-age.key
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=temp/hetzner-sops-age.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f hetzner/cluster/flux-system/gotk-sync.yaml
flux reconcile kustomization flux-system --with-source --timeout=10m
flux reconcile kustomization apps --timeout=10m
flux reconcile kustomization k3s-upgrade-plan --timeout=5m
```

The root sync installs cert-manager and waits for its HelmRelease before apps apply the ClusterIssuer and certificates. No manual cert-manager installation is needed. Traefik is supplied by K3s. DNS A/AAAA records must point to working server addresses, and public port 80 must reach Traefik for HTTP-01 issuance. New clusters obtain certificates from Let's Encrypt, subject to issuance limits.

## 5. Verify

```bash
flux check
flux get kustomizations -A
flux get helmreleases -A
kubectl -n apps get deploy,pvc,certificates,ingresses
kubectl -n system-upgrade get deploy,plan,jobs
kubectl get pv
```

Check each public route from the app table, including HTTPS certificate validation, HTTP redirects, and expected content. For Screeps, check `/api/version` and `/web/`; initial package installation can take several minutes. For Ghost, inspect page styling and an uploaded image as well as HTTP status.

Confirm applications recover after a planned reboot when downtime is convenient. This checks restart behavior; a fresh-host restore is a separate recovery check.
