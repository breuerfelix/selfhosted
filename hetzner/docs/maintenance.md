# Maintenance

Run commands from the repository root with `export KUBECONFIG="$PWD/temp/hetzner-kubeconfig"`.

## Application changes

Edit the app directory under `cluster/apps/`, validate, and push reviewed changes to `main`. Flux reconciles automatically; force a refresh with:

```bash
flux reconcile kustomization apps --with-source --timeout=10m
flux get kustomizations -A
kubectl -n apps get deploy,pvc,certificates
```

To add an app, create its `app.yaml`, `ingress.yaml`, `kustomization.yaml`, and optional `storage.yaml`/encrypted config. Add the directory to `cluster/apps/kustomization.yaml`. Use one replica and `Recreate` for a single-writer data directory. Use ClusterIP Services and one HTTPS Ingress with the shared issuer. Traefik handles HTTP redirects globally. Keep image tags and digests together.

Choose storage from data requirements: retained local PVs for important data at predictable paths, local-path PVCs for disposable data, and no PVC for stateless apps. Add retained host directories to `ansible/storage.yml`. Keep PV/PVC names, paths, and node affinity stable on an existing cluster; these are storage identities, not cosmetic settings.

Removing a resource from Git lets Flux prune it. Deleting a local-path PVC can delete its data. Retained PVs keep local files but require deliberate rebinding before reuse. Decide what to preserve before removing a stateful app.

## Secrets

Back up `temp/hetzner-sops-age.key` in a password manager. The same identity is installed in `flux-system/sops-age`; losing both copies makes committed secrets unreadable. The recipient in `cluster/apps/.sops.yaml` is public.

Screeps stores its application config directly as SOPS-encrypted YAML, consumed by Kustomize `secretGenerator`. Edit it with:

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops hetzner/cluster/apps/screeps/config.sops.yaml
```

The generated Secret name changes when config changes. Kustomize updates the Deployment reference, causing a restart and a fresh `subPath` mount. No manual version annotation or restart is needed. Every app can use the same `config.sops.yaml` naming convention: `.sops.yaml` encrypts these files completely. Other `*.sops.yaml` files use the fallback Kubernetes Secret rule, which encrypts only `data` and `stringData`. Keep the generator's default name hash enabled.

Never commit private keys, kubeconfigs, or decrypted config. `kubectl kustomize` builds ciphertext locally; Flux decrypts generated Secret values before applying them.

## Updates

| Europe/Berlin time | Action |
| --- | --- |
| 01:00 | Refresh Ubuntu package lists |
| 02:00 | Install unattended updates |
| 03:00 | Reboot when required |
| 04:00–05:00 | Allow K3s patch upgrade Jobs to start |

Ubuntu timers use no randomized delay and do not catch up missed runs. The spring daylight-saving transition skips the 02:00 run. Ubuntu's default allowed origins remain in effect; explicitly configure any third-party repositories you want updated. A long update or reboot can extend beyond its intended window.

The K3s Plan tracks one minor-version channel with no drain or cordon on the single node. A Job started in its window may finish later. For a new minor, review compatibility, advance one minor at a time, and update the Plan channel, controller's kubectl helper, and Ansible bootstrap version together. Ansible does not downgrade installed K3s.

Renovate proposes app image, Flux, and cert-manager chart updates. cert-manager component images follow the pinned chart defaults; update both OCI tag and digest when editing manually. Flux's generated `gotk-components.yaml` should be regenerated with the same three components, not hand-edited:

```bash
flux install --export --components=source-controller,kustomize-controller,helm-controller > hetzner/cluster/flux-system/gotk-components.yaml
```

Use the intended Flux CLI version for this command. The system-upgrade-controller CRD and controller YAML are vendored upstream release files with pinned controller/helper images. Update the whole release together, reviewing RBAC and CRDs as well as images. Renovate's Deployment image proposal alone does not refresh the vendored release or the helper image in its ConfigMap.

After upgrades, check Flux, node readiness, PVCs, certificates, and public routes. Upgrade Jobs expire after the configured TTL; inspect Plan status and events if Jobs are already gone.

## Routine checks

```bash
flux get kustomizations -A
flux get sources all -A
flux get helmreleases -A
kubectl get nodes -o wide
kubectl -n apps get deploy,pvc,certificates
kubectl -n apps get events --sort-by=.lastTimestamp
kubectl -n system-upgrade describe plan k3s-server
ssh cool 'df -h /; systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager'
```

For app failures, inspect the pod's events and logs. For certificate failures, inspect Certificate, CertificateRequest, Order, and Challenge objects, then check DNS and port 80. The global Traefik redirect exempts ACME challenges; its low priority lets the domain redirect take precedence. For retained storage, check the host directory, ownership, and node affinity. No declared PVC capacity enforces a filesystem quota here.

No scheduled backup runs. Maintain current off-server backups of required data before relying on [rebuild.md](rebuild.md) for recovery. Use a consistent SQLite backup method and verify a restore; do not copy actively written database files as if they were a consistent snapshot.

## Local validation

```bash
kubectl kustomize hetzner/cluster > /dev/null
kubectl kustomize hetzner/cluster/apps > /dev/null
kubectl kustomize hetzner/cluster/infrastructure/k3s-upgrade-plan > /dev/null
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/site.yml --syntax-check
```

Ansible `--check --diff` is useful on an already-configured host. A check-mode run cannot fully simulate installing missing packages or creating files needed by later tasks on a blank host.

## Moving resources between Flux syncs

Moving files within the same Flux Kustomization does not change ownership. Moving resources to another Flux Kustomization requires a staged change to avoid deleting live objects:

1. Set `prune: false` on the current owner in Git, push, reconcile, and verify the live setting.
2. Move the resources while keeping pruning disabled on that owner. Push and reconcile both syncs.
3. Use `flux tree kustomization <name>` to confirm the new owner includes the resources and the old owner's inventory no longer does.
4. Restore `prune: true` in Git and reconcile.

See [Flux's resource-move procedure](https://fluxcd.io/flux/faq/#how-can-i-safely-move-resources-from-one-dir-to-another).
