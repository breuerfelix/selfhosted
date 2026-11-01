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

Back up `temp/hetzner-sops-age.key` in a password manager. The same identity is installed in `flux-system/sops-age`; losing both copies makes committed secrets unreadable. The recipient in repository-root `.sops.yaml` is public and shared with Beelink.

Screeps stores its application config directly as SOPS-encrypted YAML, consumed by Kustomize `secretGenerator`. Edit it with:

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops hetzner/cluster/apps/screeps/config.sops.yaml
```

Run SOPS commands from the repository root so new files and `sops updatekeys` use the shared root creation rules. Existing encrypted files also carry their recipients.

The generated Secret name changes when config changes. Kustomize updates the Deployment reference, causing a restart and a fresh `subPath` mount. No manual version annotation or restart is needed. Every app can use the same `config.sops.yaml` naming convention: `.sops.yaml` encrypts these files completely. Other `*.sops.yaml` files use the fallback Kubernetes Secret rule, which encrypts only `data` and `stringData`. Keep the generator's default name hash enabled.

Never commit private keys, kubeconfigs, or decrypted config. `kubectl kustomize` builds ciphertext locally; Flux decrypts generated Secret values before applying them.

## Updates

Hetzner and Beelink use the same [shared maintenance policy](../../shared/README.md): Ubuntu package updates and conditional reboots, K3s patch upgrades, Flux components, and Ansible bootstrap tasks. Schedules, allowed origins, shared release updates, validation, and rollout checks are documented there.

Renovate proposes app image, shared Flux/controller image, and cert-manager chart updates. cert-manager component images follow the pinned chart defaults; update both OCI tag and digest when editing manually.

After upgrades, check Flux, node readiness, PVCs, certificates, and public routes. No scheduled backup runs; keep current off-server backups and verify restore procedures.

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
kubectl kustomize shared/cluster/k3s-upgrade-plan > /dev/null
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
