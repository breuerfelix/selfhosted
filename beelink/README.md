# Beelink K3s

Single-node K3s on `ssh bee`, managed by Flux from this repository. Nanobot gateway/WebUI and Grafana, Loki, and single-node VictoriaMetrics run in K3s. Docker cAdvisor, vmagent, and Restic have been retired. Both Screeps agents now run in K3s; their original Docker containers are stopped with restart disabled. Public metrics/log ingestion is verified; the private server rejects its preserved token with HTTP 401. Room Planner is stopped on Docker with its Flux staging suspended. See [agent validation, private-token action, and rollback](docs/screeps-migration.md).

**Papra migrated on 1 November 2026.** Open [Papra](https://papra.vulture-skink.ts.net/) over Tailscale HTTPS. Original database, five documents, user, and auth secret are preserved at `/data/papra`; the old Docker container stays stopped. Papra backups are disabled. See [deployment and rollback](docs/papra.md).

**Monitoring migrated on 1 November 2026.** Open [Grafana](https://grafana.vulture-skink.ts.net/) over Tailscale HTTPS with existing credentials. Loki and VictoriaMetrics have internal ClusterIP Services; no monitoring LAN ports are published. Original SSD paths, pinned versions, dashboards, credentials, and history are preserved. Old Docker backends remain stopped with restart disabled, and shared Portainer stack 26 automatic updates stay disabled. See [monitoring verification, backups, and rollback](docs/monitoring.md).

**Nanobot migrated on 31 October 2026.** K3s, Flux, and the Tailscale operator are Ready. Nanobot runs from a tested GitHub Actions build of pinned upstream sources, using its original SSD mount. Open [nanobot](https://nanobot.vulture-skink.ts.net/) with Tailscale connected and use the existing WebUI password. Both old Docker nanobot containers and their local image have been removed. The old Docker subnet router was also stopped on 1 November after Pi-hole joined Tailscale directly; only Hermes and Hindsight remain running on Docker. See [verified status](docs/status.md), [image build](images/nanobot/README.md), [authentication steps](docs/tailscale.md), and [the bootstrap and cutover runbook](docs/bootstrap.md).

```text
beelink/
  ansible/                    # Host-specific configuration, SSD checks, shared-role wrappers
  cluster/flux-system/        # Independent Git source; shared Flux components
  cluster/infrastructure/     # Tailscale Helm release; encrypted OAuth Secret added at setup
  cluster/apps/               # Nanobot, monitoring, Papra; retained storage and private ingress
  cluster/*-sync.yaml         # Staged Flux reconciliation
  images/nanobot/             # Upstream source pin, image smoke test, digest update helper
  scripts/                    # Local SOPS credential helper
  templates/                  # Credential template, never a filled plaintext secret
  .sops.yaml                  # Same public age recipient as Hetzner
```

**Docker retirement:** Only Hermes and Hindsight remain running. Portainer and other retained containers are stopped with restart disabled; cAdvisor, vmagent, Restic and old Nanobot containers are removed. See [inventory and recovery implications](docs/docker-retirement.md).

**Backups:** K3s application backups remain disabled. Docker Restic has been removed; its scheduled backups no longer run. Existing off-host repositories and native Hermes archives remain intact.

All application persistence uses static retained local PVs at each app's existing Docker bind-mount source path. Nanobot keeps `/data/nanobot` mounted at `/home/nanobot/.nanobot`. No copying, formatting, replacement storage tree, or recursive ownership change is part of migration. K3s state and container images use the internal system disk at `/var/lib/rancher/k3s`.

Tailscale provides private HTTPS for the nanobot UI. Pi-hole runs separately and provides tailnet DNS. Flux reads public GitHub over HTTPS; it does not require a GitHub token. The Tailscale operator's OAuth credentials are encrypted with SOPS. GitHub Actions builds/publishes images with its built-in token; the GHCR package is public for anonymous cluster pulls.

**LAN access:** ServiceLB is enabled. Nanobot also serves [HTTP on LAN port 8765](http://192.168.178.13:8765/), using the same pod and data. LAN exposure is opt-in through each app's `lan.yaml`; Traefik stays disabled. See [the ServiceLB pattern and verification](docs/servicelb-plan.md).

Both hosts use the [shared maintenance code and policy](../shared/README.md): nightly Ubuntu updates and conditional reboot, K3s patch upgrades, Flux components, and common K3s bootstrap tasks. `ansible/site.yml` configures updates and K3s together.
