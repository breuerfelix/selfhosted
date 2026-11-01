# Beelink K3s

Single-node K3s on Ubuntu 24.04, reached through `ssh bee`. Ansible configures the host; Flux deploys this repository's `main` branch. Tailscale provides private HTTPS. ServiceLB provides opt-in LAN ports; Traefik and dynamic local storage are disabled.

| Application | Namespace | Access | Persistent host path | UID:GID |
| --- | --- | --- | --- | --- |
| Nanobot | `nanobot` | [Tailscale HTTPS](https://nanobot.vulture-skink.ts.net/), [LAN HTTP](http://192.168.178.13:8765/) | `/data/nanobot` | `1000:1000` |
| Papra | `papra` | [Tailscale HTTPS](https://papra.vulture-skink.ts.net/) | `/data/papra` | `1000:1000` |
| Grafana | `monitoring` | [Tailscale HTTPS](https://grafana.vulture-skink.ts.net/) | `/data/grafana` | `0:0` |
| Loki | `monitoring` | ClusterIP, TCP 3100 | `/data/loki` | `10001:10001` |
| VictoriaMetrics | `monitoring` | ClusterIP, TCP 8428 | `/data/victoriametrics` | `0:0` |
| Screeps agents | `screeps-agent` | Outbound connections only | None | Image default |

Persistent applications use one replica, `Recreate`, and retained static local PVs on the `/data` SSD. The K3s service requires that filesystem and verifies its UUID before startup. K3s state and container images live under `/var/lib/rancher/k3s` on the system disk. Declared PV capacities do not enforce disk quotas. No scheduled application backup is configured.

```text
beelink/
  ansible/                 # Host configuration and SSD guard
  cluster/
    flux-system/           # Host root sync; shared controllers and Git source
    apps-sync.yaml         # App reconciliation and dependency order
    tailscale-sync.yaml
    room-planner-sync.yaml # Suspended
    infrastructure/tailscale/
    apps/                  # Manifests, storage, encrypted secrets
  docs/                    # Rebuild, maintenance, Tailscale, Google OAuth
  images/                  # Custom image sources and builds
  scripts/                 # Room Planner registry helper
```

`apps-sync.yaml` keeps independent reconciliation for Nanobot, Papra, monitoring, and Screeps agents. The first three depend on Tailscale; Screeps agents depend on monitoring readiness. Room Planner remains suspended and needs separate application/registry work.

Versions and image digests live in manifests. Renovate proposes standard app and Helm chart updates. Nanobot's [image workflow](images/nanobot/README.md) builds and tests custom images, then proposes the deployment digest. Custom Nanobot and Room Planner images are excluded from direct Renovate updates.

Both hosts share [host maintenance, Flux components, the Git source, and K3s upgrades](../shared/README.md). Repository-root `.sops.yaml` defines encryption rules for both hosts. Public Git and Nanobot image pulls need no registry credentials.

- [Rebuild](docs/rebuild.md)
- [Maintenance, secrets, LAN access, and Screeps](docs/maintenance.md)
- [Tailscale authentication](docs/tailscale.md)
- [Nanobot Google Workspace OAuth](docs/google-workspace.md)
