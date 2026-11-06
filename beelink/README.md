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
| Room Planner | `room-planner` | [Tailscale HTTPS](https://room-planner.vulture-skink.ts.net/) | None | Image default |

Persistent applications use one replica, `Recreate`, and retained static `hostPath` PVs on the `/data` SSD. The K3s service requires that filesystem and verifies its UUID before startup. K3s state and container images live under `/var/lib/rancher/k3s` on the system disk. Declared PV capacities do not enforce disk quotas. The [nightly S3 backup](../shared/cluster/backups/README.md) ships suspended until setup is complete.

Hermes and Hindsight run separately in Docker. Their standalone deployment definition is `/opt/hermes/compose.json` on the host; it contains credentials and is readable only by root. See [Docker operations](docs/docker.md).

```text
beelink/
  ansible/                 # Host configuration and SSD guard
  cluster/
    flux-system/           # Cluster root sync
    shared-sync.yaml       # Shared components and backup patches
    apps-sync.yaml         # One sync for all active apps, after Tailscale
    tailscale-sync.yaml
    infrastructure/tailscale/
    apps/                  # Manifests, storage, encrypted secrets
  docs/                    # Rebuild, maintenance, authentication, app operations
  images/nanobot/          # Custom Nanobot image source and build helpers
  scripts/                 # Nanobot token helper
```

`apps-sync.yaml` reconciles Nanobot, Papra, monitoring, Screeps agents, and Room Planner together through `apps/kustomization.yaml`, matching Hetzner's layout. Tailscale readiness gates the whole group; application health is checked together with a 15-minute timeout. Monitoring and Screeps agents can start concurrently, so initial collection attempts can fail while backends start. Room Planner exposes only a Tailscale HTTPS ingress and uses no persistent storage.

Versions and image digests live in manifests. Renovate proposes standard app and Helm chart updates, including digest updates for Room Planner's `latest` tag. Nanobot's [image workflow](images/nanobot/README.md) builds and tests custom images, then proposes the deployment digest. Only the custom Nanobot image is excluded from direct Renovate updates.

Both hosts share [host maintenance, Flux components, the Git source, and K3s upgrades](../shared/README.md). Repository-root `.sops.yaml` defines encryption rules for both hosts. Public Git, Nanobot, and Room Planner image pulls need no registry credentials.

- [Rebuild](docs/rebuild.md)
- [Maintenance, secrets, LAN access, and Screeps](docs/maintenance.md)
- [Tailscale authentication and Pi-hole DNS](docs/tailscale.md)
- [Nanobot Google Workspace OAuth](docs/google-workspace.md)
- [Room Planner image and access](docs/room-planner.md)
- [Docker operations](docs/docker.md)
