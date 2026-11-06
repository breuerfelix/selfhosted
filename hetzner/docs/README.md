# Personal VPS

One Ubuntu 24.04 VPS running K3s, Flux, and personal applications. Downtime is acceptable. Keep upstream defaults and plain manifests; no HA or distributed storage.

- [Rebuild](rebuild.md): prerequisites, host setup, data restore, and Flux bootstrap.
- [Maintenance](maintenance.md): app changes, secrets, updates, and troubleshooting.
- [Shared maintenance](../../shared/README.md): common host policy, K3s upgrades, and Flux components.

## Layout

```text
hetzner/
  ansible/                 # Host setup; site.yml runs all playbooks
  cluster/
    flux-system/          # Cluster root sync
    shared-sync.yaml      # Shared components and backup patches
    infrastructure/       # cert-manager and Traefik config
    apps/                 # Shared namespace/issuer and app directories
  docs/
```

Each app owns its workload, service, ingress, configuration, and storage definitions. Stateful apps have a `storage.yaml`; stateless apps do not. The redirect uses native Traefik routes and needs no pod.

## Components

- **K3s:** single server with SQLite, bundled containerd, Traefik, ServiceLB, CoreDNS, and local-path storage. Ansible installs the initial version; the Flux-managed upgrade Plan handles later patches.
- **Flux:** source, Kustomize, and Helm controllers. Uses the shared Git source to read this public GitHub repository over HTTPS without Git credentials. The root sync installs infrastructure and waits for cert-manager. The `apps` sync depends on root readiness. A shared parent creates separate syncs for Flux itself, the upgrade controller, and its Plan; the Plan waits for upgrade-controller readiness. Upgrade-controller rollout health does not block app reconciliation. Apps have their own rollout health checks.
- **DNS and TLS:** wildcard DNS points to the VPS. Each app declares its Ingress and TLS configuration; cert-manager issues and renews Let's Encrypt certificates through HTTP-01. Traefik redirects HTTP to HTTPS globally, allows ACME challenges, and preserves the direct domain redirect.
- **Secrets:** SOPS with age. Encrypted config stays in Git; the private key belongs in a password manager and `flux-system/sops-age`.
- **Storage:** retained `hostPath` PVs for data that must survive claim deletion; local-path PVCs for disposable data. Capacity declarations do not enforce disk quotas. All data shares the server disk.

| App | Public host | Storage | Recovery policy |
| --- | --- | --- | --- |
| Ghost | `danielkueffler.de` | `/data/ghost` | Restore content and SQLite database |
| Fathom | `stats.felixbreuer.me` | `/data/fathom` | Restore SQLite database |
| Screeps | `screeps.felixbreuer.me` | `/data/screeps` | Restore world and player data; config is in Git |
| Noobgallery | `photos.felixbreuer.me` | None | Recreate from image |
| Redirect | `felixbreuer.me` → `https://breuer.dev/` | None | Recreate from Git |

These policies describe data requirements, not different deployment procedures. All apps reconcile through the same Flux sync.

## Source of truth

Versions and image digests live in manifests, not documentation. Renovate proposes app images, Flux manifests, and cert-manager chart updates. Review before merging to `main`: Flux applies merged changes automatically.

Host configuration lives in Ansible. Application data lives under `/data` on the VPS and is not reconstructed from Git. The [nightly S3 backup](../../shared/cluster/backups/README.md) ships suspended until setup is complete. No ad hoc volume backups are required before changes or rollouts. Keep the age identity separately recoverable. `Retain` preserves local files after claim deletion; it does not protect against disk loss.
