# Bootstrap and nanobot cutover

All local commands run from the repository root. See the current state below for completed steps. Tools: SSH, uv/Python, Ansible, kubectl, Flux, SOPS, age. Use a kubectl client within the supported minor-version skew of the selected K3s release.

**Current state:** K3s, Flux, the Tailscale operator, and nanobot are running. Image build and cutover completed; see [status](status.md). The procedure below is retained for rebuilds, migration, and rollback. During recovery, stop all writers and restore/verify SSD data before allowing the enabled nanobot sync to run.

## 1. Final preflight and Git preparation

- Review the files and current `ssh bee` inventory again; confirm `/data` still has the UUID in `ansible/k3s.yml`.
- Confirm nanobot image ID, config, health, and backup freshness. Record both Docker restart policies (`unless-stopped` at inventory).
- Confirm router DHCP reservation for the current LAN IP, or plan to use the SSH tunnel below. Verify existing router forwards do not expose Kubernetes ports; UFW is currently inactive.
- For a first migration or restore, set nanobot's sync to suspended in Git until storage and stopped-writer checks are complete. The live repository now enables it. Tailscale can run before authentication; the operator pod waits for its OAuth Secret. Include only reviewed changes when committing; unrelated Hetzner edits may exist locally.

## 2. Bootstrap K3s without stopping Docker

```bash
uv venv temp/ansible-venv
uv pip install --python temp/ansible-venv/bin/python -r beelink/ansible/requirements.txt
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/k3s.yml
ssh bee 'k3s kubectl get nodes -o wide; systemctl show k3s -p RequiresMountsFor -p BindsTo; findmnt /data'
```

The playbook installs K3s, adds an SSD startup dependency, and leaves Docker apps running. It does not format storage, create app data directories, change ownership, change networking on the router, or upgrade an existing K3s binary. Confirm other Docker apps still work after installation; K3s adds host networking rules.

Copy a private kubeconfig and either use the current LAN address or an SSH tunnel:

```bash
(umask 077; ssh bee 'cat /etc/rancher/k3s/k3s.yaml' > temp/beelink-kubeconfig)
chmod 600 temp/beelink-kubeconfig
```

For direct LAN access, edit its server from `https://127.0.0.1:6443` to `https://192.168.178.13:6443`. For a tunnel, keep the loopback address but change its port to `16443`, then run this in a separate terminal:

```bash
ssh -N -L 127.0.0.1:16443:127.0.0.1:6443 bee
```

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
kubectl get nodes -o wide
```

The image pipeline is described in [images/nanobot/README.md](../images/nanobot/README.md). It builds/tests upstream sources and opens a Deployment digest PR. Merge the desired tested digest, then verify K3s can pull it anonymously before cutover. No Docker image import is needed.

## 3. Install Flux and the existing age identity

```bash
kubectl apply -f beelink/cluster/flux-system/gotk-components.yaml
kubectl wait --for=condition=Established --timeout=120s \
  crd/gitrepositories.source.toolkit.fluxcd.io \
  crd/kustomizations.kustomize.toolkit.fluxcd.io \
  crd/helmrepositories.source.toolkit.fluxcd.io \
  crd/helmreleases.helm.toolkit.fluxcd.io
kubectl -n flux-system rollout status deployment/source-controller --timeout=180s
kubectl -n flux-system rollout status deployment/kustomize-controller --timeout=180s
kubectl -n flux-system rollout status deployment/helm-controller --timeout=180s
```

Use the existing protected `temp/hetzner-sops-age.key` or restore that same identity from its backup. Verify its public recipient matches `beelink/.sops.yaml` without printing the private identity:

```bash
chmod 600 temp/hetzner-sops-age.key
age-keygen -y temp/hetzner-sops-age.key
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=temp/hetzner-sops-age.key \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f beelink/cluster/flux-system/gotk-sync.yaml
flux reconcile kustomization flux-system --with-source --timeout=10m
flux get kustomizations -A
```

Root must reconcile successfully, with nanobot still suspended. Tailscale reconciliation can remain not Ready until OAuth credentials are supplied. No app starts at this step. Keep the private key in the existing secure backup; never commit it.

## 4. Prepare Tailscale, encrypt credentials, then activate its sync

In the existing Tailscale policy, merge these tag ownership entries without replacing other policy sections:

```json
{
  "tagOwners": {
    "tag:k8s-operator": [],
    "tag:k8s": ["tag:k8s-operator"]
  }
}
```

Create the operator OAuth client using the scopes in [the reviewed design](design.md). Enable MagicDNS and HTTPS, check `nanobot` is an available hostname, and ensure the existing grants/ACLs permit intended clients to reach `tag:k8s` on TCP 443. No global DNS override or subnet-route removal is needed.

Fill the credential template using a local editor, then encrypt it:

```bash
(umask 077; cp beelink/templates/operator-oauth.yaml.example temp/beelink-operator-oauth.yaml)
chmod 600 temp/beelink-operator-oauth.yaml
# Edit temp/beelink-operator-oauth.yaml with the real client ID and secret.
sops --config beelink/.sops.yaml encrypt \
  --filename-override beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml \
  temp/beelink-operator-oauth.yaml \
  > beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml
rm temp/beelink-operator-oauth.yaml
```

Add `operator-oauth.sops.yaml` to that directory's `kustomization.yaml`. Set `spec.suspend: false` in `cluster/tailscale-sync.yaml`. Keep nanobot suspended. Review that `stringData` is encrypted and the age recipient matches Hetzner; commit and push only the reviewed changes. For later edits:

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml
```

```bash
flux reconcile kustomization flux-system --with-source --timeout=10m
flux reconcile kustomization tailscale --timeout=10m
flux get helmreleases -A
kubectl -n tailscale rollout status deployment/operator --timeout=300s
kubectl get ingressclass tailscale
```

Verify `beelink-k8s-operator` joined the tailnet. If credentials, tags, permissions, or deployment readiness fail, fix them while Docker nanobot remains available. Do not activate nanobot yet.

## 5. Cut nanobot over

Confirm the pinned image can be pulled and the operator is healthy. Verify old Portainer automatic stack redeployment is disabled. Then disable both restart policies, stop both shared-directory writers, and confirm they are stopped:

```bash
ssh bee 'docker update --restart=no nanobot nanobot-api && docker stop nanobot-api nanobot'
ssh bee 'docker inspect nanobot nanobot-api --format "{{.Name}} running={{.State.Running}} restart={{.HostConfig.RestartPolicy.Name}}"'
```

Both must show `running=false`. Verify a current consistent backup while all writers are stopped, using the existing backup procedure. Do not run a second writer to create that backup.

Set `spec.suspend: false` in `cluster/nanobot-sync.yaml`; commit and push that change. Then:

```bash
flux reconcile kustomization flux-system --with-source --timeout=10m
flux reconcile kustomization nanobot --timeout=10m
kubectl -n nanobot rollout status deployment/nanobot --timeout=300s
kubectl -n nanobot get pods,pvc,svc,ingress
kubectl get pv nanobot-data
```

Use the actual address reported by `kubectl -n nanobot get ingress nanobot` with `https://`. Initial certificate provisioning can take time. The old LAN host ports 8765, 18790, and 8900 are intentionally not recreated by Kubernetes.

Verify UI login, existing sessions/workspace, WebSocket chat and a real provider/tool request. Test on home Wi-Fi and cellular with Tailscale enabled; verify HTTPS and absence of Funnel/public access. Check pod logs locally, avoiding copied provider tokens. Confirm only the Kubernetes process now writes `/data/nanobot` and other Docker apps still work.

Keep stopped containers for initial rollback. Their restart policies and Portainer GitOps updates must stay disabled; do not manually redeploy the old stack while Kubernetes owns the mount. Verify the existing nanobot backup procedure against the Kubernetes workload before the next backup run. Schedule a controlled reboot later to check SSD-before-K3s startup and app recovery.

## 6. Rollback

First set `spec.suspend: true` in `cluster/nanobot-sync.yaml`, commit/push, and reconcile the root. Then scale down and wait for pods to disappear:

```bash
flux reconcile kustomization flux-system --with-source --timeout=10m
flux get kustomizations -A
kubectl -n nanobot scale deployment/nanobot --replicas=0
kubectl -n nanobot wait --for=delete pod -l app=nanobot --timeout=180s
```

Verify nanobot reconciliation is suspended and no nanobot pod is running. For emergency rollback before Git is available, suspend the root sync first, then the nanobot sync, before scaling down; otherwise root can undo the child suspension. Commit the suspended state before resuming the root.

Only after Kubernetes has stopped writing, restart the original gateway:

```bash
ssh bee 'docker update --restart=unless-stopped nanobot && docker start nanobot'
```

Keep `nanobot-api` stopped. Restore a stopped-writer backup only if data compatibility requires it. No PV deletion, directory move, chown, Pi-hole change, or Tailscale router removal is required for rollback.

## Validation before deployment

```bash
temp/ansible-venv/bin/ansible-playbook -i beelink/ansible/inventory.ini beelink/ansible/k3s.yml --syntax-check
bash -n beelink/images/nanobot/smoke-test.sh
python3 beelink/images/nanobot/build-metadata.py
kubectl kustomize beelink/cluster > temp/beelink-root-rendered.yaml
kubectl kustomize beelink/cluster/infrastructure/tailscale > temp/beelink-tailscale-rendered.yaml
kubectl kustomize beelink/cluster/apps/nanobot > temp/beelink-nanobot-rendered.yaml
```

These checks validate local rendering and syntax. They do not prove live K3s/Docker networking, OAuth enrollment, SSD reboot behavior, or browser/WebSocket behavior. Those acceptance checks require deployment.
