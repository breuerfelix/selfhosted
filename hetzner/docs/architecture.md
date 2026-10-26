# Target architecture

Status: target design, partly implemented. Updated 2026-10-26. Ubuntu update schedule, K3s, Flux, and Ghost/Fathom static PVs/PVCs are deployed. SOPS age decryption is configured. Ghost, Fathom, redirect, and Noobgallery run internally; Screeps remains inactive. K3s packages Traefik, but no public application routes exist yet.

## Goals and accepted constraints

- One Hetzner VPS, Ubuntu 24.04 LTS, one K3s server. No HA or distributed storage.
- Git repository `git@github.com:breuerfelix/selfhosted.git` is source of truth for host provisioning code, Flux configuration, and application manifests. New implementation and documentation belong under `hetzner/`.
- User accepts downtime lasting days. Migration occurs on existing VPS; no parallel server or DNS cutover is required.
- Preserve Ghost and Fathom data. Screeps data may be lost. Keep old Coolify folders until new apps and recovery path have been checked.
- Backup destination is this Mac, inside repository `temp/`, excluded from Git by root `.gitignore`. This is one Mac-local copy, not independently replicated or versioned by Git.
- User wants guided, checkpoint-based execution. Do not perform all stages autonomously.

## Proposed components

| Concern | Choice | Notes |
| --- | --- | --- |
| Kubernetes | K3s single server, default embedded SQLite | `v1.36.5+k3s1` running with systemd enabled. Node and CoreDNS/local-path/metrics-server are Ready. No etcd or external database. |
| Storage | Static local PVs with `Retain` for important data | `/srv/k3s-data/ghost` and `/srv/k3s-data/fathom` contain verified copies. PVs/PVCs are Bound in the `apps` namespace and use explicit paths. Predictable paths support fresh-host restore without dynamically generated PV directory names. K3s local-path provisioner remains for Screeps' disposable, unbacked-up PVC. |
| GitOps | Flux v2.9.6 under `hetzner/cluster/flux-system` | Deployed: source, Kustomize, and Helm controllers. Flux reads public GitHub repository anonymously over HTTPS. Mac uses its existing SSH credentials for Git pushes. No Flux Git credential is needed for recovery while repository stays public. |
| Secrets | SOPS with age, consumed by Flux | Screeps config is encrypted in Git. Flux has private age key in `flux-system/sops-age`; Mac key file is ignored by Git and needs a password-manager backup. No encrypted app Secret has been deployed yet. |
| Ingress | K3s-packaged Traefik and ServiceLB | Keep packaged chart at K3s defaults. K3s supplies a compatible Traefik chart with its release; advance Traefik with K3s upgrades rather than a separate Flux HelmRelease. Only add a `HelmChartConfig` if a concrete setting is needed. No MetalLB or Hetzner cloud controller. No public application routes yet. |
| TLS | cert-manager with Let's Encrypt HTTP-01 | Automatic renewal after public ingress is working. Existing Coolify certificates need not be migrated. |
| Ubuntu updates | `unattended-upgrades` with automatic reboot | Applied via `hetzner/ansible/ubuntu-updates.yml`: refresh 01:00, install 02:00, reboot at 03:00 if required, all Europe/Berlin. Keep future backup/K3s upgrade windows separate. |
| K3s updates | system-upgrade-controller with a maintenance window | Ansible's `v1.36.5+k3s1` version is first-install bootstrap only; it skips installer once binary exists and must not downgrade future versions. Flux will later install controller and one server Plan tracking `v1.36` patch channel. Advance minor version through reviewed Git change. Exact window still needs selection. |
| Backup | Mac-initiated copy of Ghost and Fathom only | One verified migration archive exists. Ongoing backup schedule and consistency mechanism still need a decision. If Mac is off or lost, this backup is unavailable. |

Avoid Longhorn, Velero, MetalLB, external databases, and extra controllers without a concrete need. Pin each image to a digest, including registries that publish only `latest`; update them through reviewed Git changes.

## Intended repository layout

```text
hetzner/
  docs/                 # This handoff, architecture, migration and recovery
  ansible/              # Host configuration, updates, directories, K3s install
  cluster/
    flux-system/        # Flux bootstrap output
    infrastructure/     # cert-manager, upgrade controller, storage
    apps/               # Namespaces, workloads, Services, Ingresses, secrets
  backup/               # Mac-side backup/restore scripts if ongoing backup chosen
```

`hetzner/docs/`, initial `hetzner/ansible/` playbooks, Flux self-management manifests, Ghost/Fathom storage manifests, and five application manifests exist now. Four apps are active internally; Screeps is inactive. Application Ingress resources and ongoing backup automation do not exist. Keep all new Flux files and docs under `hetzner/`.

## Applications to migrate (five)

Current app definitions are in `coolify/applications/*/docker-compose.yaml`. Treat these as migration references, not authoritative Kubernetes manifests. Coolify-generated routing labels are absent; verify routes during implementation.

| App | Public host | Existing image | Persistent source on VPS |
| --- | --- | --- | --- |
| Ghost (`danielkueffler`) | `danielkueffler.de` | `ghost:5-alpine` | `/data/coolify/applications/daniel` → `/var/lib/ghost/content` |
| Fathom | `stats.felixbreuer.me` | `usefathom/fathom:version-1.2.1` | `/data/coolify/applications/fathom` → `/data` |
| Screeps | `screeps.felixbreuer.me` | `screepers/screeps-launcher:latest` | `/data/coolify/applications/screeps` → `/screeps`; disposable per user |
| Redirect | `felixbreuer.me` | `grahamdigital/simple-redirect:latest` | None |
| Noobgallery | `photos.felixbreuer.me` | `felixbreuer/noobgallery:latest` | None |

Travian inactive finder and idle proxy are retired by user choice. Their stopped Coolify containers and legacy repository definitions remain only as historical rollback material; do not deploy them on K3s or include their routes in ingress.

Screeps' stopped container mounted `/data/coolify/applications/u8ckco8wk8o84wgw00s0044o/screeps/config.yml` to `/screeps/config.yml`. That source was nonempty (506 bytes); `/data/coolify/applications/screeps/config.yml` was empty. The nonempty config is preserved as a SOPS-encrypted Secret in Git. Redirect app's `PROTOCOL` and `REDIRECT_TO` values were recovered from its stopped container; see [app-preparation.md](app-preparation.md).

Old `/data/coolify/applications/screeps2` and `screeps3` folders exist but no corresponding running containers were found. They are outside current migration scope unless user decides otherwise.

## Recovery model

Primary rebuild path: provision Ubuntu/K3s from `hetzner/ansible`, apply committed Flux manifests from `hetzner/cluster/flux-system`, restore SOPS age key, restore Ghost/Fathom files to deterministic paths, then let Flux reconcile manifests. The public repository needs no Flux Git credential. Cluster resources should be disposable and reproducible from Git. For faster same-host recovery, a consistent K3s SQLite datastore copy plus `/var/lib/rancher/k3s/server/token` can be added later; token is required to restore that datastore. Do not treat raw SQLite copy taken during writes as a tested backup.

Before declaring migration complete: verify Ghost/Fathom content, all five planned routes, TLS issuance, Flux reconciliation, automatic recovery after reboot, and a restore of the Mac backup. Keep old Coolify files until those checks pass.

## Open implementation choices

1. Choose ongoing backup cadence and how Mac initiates it. Mac availability is a direct constraint; current archive is only a migration backup.
2. Choose K3s minor channel and separate K3s upgrade window from Ubuntu's 01:00/02:00/03:00 Berlin schedule. Host timezone is now Europe/Berlin.
3. Decide whether Screeps starts empty or its existing data is copied once. Its configuration must still be migrated.
4. Tighten Hetzner Cloud Firewall API rule when convenient: user reported TCP 6443 is currently allowed from anywhere. API requires valid client credentials, but source-limiting it to Mac IP would reduce exposure. Hetzner firewall configuration cannot be read over SSH; fresh SSH and Mac API access have been tested. Keep TCP 22 allowed until new source restrictions are tested.

## References

- K3s datastore and backup: https://docs.k3s.io/datastore and https://docs.k3s.io/datastore/backup-restore
- K3s local storage: https://docs.k3s.io/add-ons/storage
- K3s automated upgrades: https://docs.k3s.io/upgrades/automated
- Flux public Git sources and SOPS: https://fluxcd.io/flux/components/source/gitrepositories/ and https://fluxcd.io/flux/guides/mozilla-sops/
- Ubuntu unattended upgrades: https://documentation.ubuntu.com/security/security-updates/
