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

Persistent applications use one replica, `Recreate`, and retained static `hostPath` PVs on the `/data` SSD. The K3s service requires that filesystem and verifies its UUID before startup. K3s state and container images live under `/var/lib/rancher/k3s` on the system disk. Declared PV capacities do not enforce disk quotas. No scheduled application backup is configured.

```text
beelink/
  ansible/                 # Host configuration and SSD guard
  cluster/
    flux-system/           # Cluster root sync
    shared-sync.yaml       # Entry point for shared component syncs
    apps-sync.yaml         # One sync for all active apps, after Tailscale
    tailscale-sync.yaml
    room-planner-sync.yaml # Suspended
    infrastructure/tailscale/
    apps/                  # Manifests, storage, encrypted secrets
  docs/                    # Rebuild, maintenance, Tailscale, Google OAuth
  images/                  # Custom image sources and builds
  scripts/                 # Nanobot token and Room Planner registry helpers
```

`apps-sync.yaml` reconciles Nanobot, Papra, monitoring, and Screeps agents together through `apps/kustomization.yaml`, matching Hetzner's layout. Tailscale readiness gates the whole group; application health is checked together with a 15-minute timeout. Monitoring and Screeps agents can start concurrently, so initial collection attempts can fail while backends start. Room Planner stays excluded from the group, with its separate sync suspended until application/registry work is complete.

Existing clusters need the [one-time ownership migration](docs/maintenance.md#consolidate-existing-app-syncs) before deploying this layout.

Versions and image digests live in manifests. Renovate proposes standard app and Helm chart updates. Nanobot's [image workflow](images/nanobot/README.md) builds and tests custom images, then proposes the deployment digest. Custom Nanobot and Room Planner images are excluded from direct Renovate updates.

Both hosts share [host maintenance, Flux components, the Git source, and K3s upgrades](../shared/README.md). Repository-root `.sops.yaml` defines encryption rules for both hosts. Public Git and Nanobot image pulls need no registry credentials.

- [Rebuild](docs/rebuild.md)
- [Maintenance, secrets, LAN access, and Screeps](docs/maintenance.md)
- [Tailscale authentication](docs/tailscale.md)
- [Nanobot Google Workspace OAuth](docs/google-workspace.md)
