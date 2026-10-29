# Personal VPS

One Ubuntu 24.04 VPS running K3s, Flux, and personal applications. Downtime is acceptable. Keep upstream defaults and plain manifests; no HA or distributed storage.

- [Rebuild](rebuild.md): prerequisites, host setup, data restore, and Flux bootstrap.
- [Maintenance](maintenance.md): app changes, secrets, updates, and troubleshooting.

## Layout

```text
hetzner/
  ansible/                 # Host setup; site.yml runs all playbooks
  cluster/
    flux-system/          # Generated Flux components and Git sync
    infrastructure/       # cert-manager, Traefik config, K3s updates
    apps/                 # Shared namespace/issuer and app directories
  docs/
```

Each app owns its workload, service, ingress, configuration, and storage definitions. Stateful apps have a `storage.yaml`; stateless apps do not. The redirect uses native Traefik routes and needs no pod.

## Components

- **K3s:** single server with SQLite, bundled containerd, Traefik, ServiceLB, CoreDNS, and local-path storage. Ansible installs the initial version; the Flux-managed upgrade Plan handles later patches.
- **Flux:** source, Kustomize, and Helm controllers. Reads this public GitHub repository over HTTPS without Git credentials. The root sync installs infrastructure and waits for cert-manager and system-upgrade-controller. The `apps` and `k3s-upgrade-plan` syncs depend on root readiness. Apps have their own rollout health checks.
- **TLS:** cert-manager issues and renews Let's Encrypt certificates through HTTP-01. Traefik redirects HTTP to HTTPS globally, allows ACME challenges, and preserves the direct domain redirect.
- **Secrets:** SOPS with age. Encrypted config stays in Git; the private key belongs in a password manager and `flux-system/sops-age`.
- **Storage:** retained local PVs for data that must survive claim deletion; local-path PVCs for disposable data. Capacity declarations do not enforce disk quotas. All data shares the server disk.

| App | Public host | Storage | Recovery policy |
| --- | --- | --- | --- |
| Ghost | `danielkueffler.de` | `/srv/k3s-data/ghost` | Restore content and SQLite database |
| Fathom | `stats.felixbreuer.me` | `/srv/k3s-data/fathom` | Restore SQLite database |
| Screeps | `screeps.felixbreuer.me` | `local-path` PVC | World data is disposable; config is in Git |
| Noobgallery | `photos.felixbreuer.me` | None | Recreate from image |
| Redirect | `felixbreuer.me` → `https://breuer.dev/` | None | Recreate from Git |

These policies describe data requirements, not different deployment procedures. All apps reconcile through the same Flux sync.

## Source of truth

Versions and image digests live in manifests, not documentation. Renovate proposes app images, Flux manifests, and cert-manager chart updates. Review before merging to `main`: Flux applies merged changes automatically.

Host configuration lives in Ansible. Application data lives on the VPS and is not reconstructed from Git. **No scheduled backup is configured.** Keep current, consistent off-server backups of data you want to retain and keep the age identity separately recoverable. `Retain` preserves local files after claim deletion; it does not protect against disk loss.
