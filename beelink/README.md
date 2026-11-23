# Beelink K3s

Single-node K3s on Ubuntu 24.04, reached through `ssh bee`. All applications use K3s and its bundled containerd. Ansible configures the host; Flux deploys this repository's `main` branch. Tailscale provides private HTTPS. ServiceLB provides opt-in LAN ports; Traefik and dynamic local storage are disabled.

| Application | Namespace | Access | Persistent host path | UID:GID |
| --- | --- | --- | --- | --- |
| Nanobot | `nanobot` | [Tailscale HTTPS](https://nanobot.vulture-skink.ts.net/), [LAN HTTP](http://192.168.178.13:8765/) | `/data/nanobot` | `1000:1000` |
| Papra | `papra` | [Tailscale HTTPS](https://papra.vulture-skink.ts.net/) | `/data/papra` | `1000:1000` |
| Grafana | `monitoring` | [Tailscale HTTPS](https://grafana.vulture-skink.ts.net/) | `/data/grafana` | `0:0` |
| Loki | `monitoring` | ClusterIP, TCP 3100 | `/data/loki` | `10001:10001` |
| VictoriaMetrics | `monitoring` | ClusterIP, TCP 8428 | `/data/victoriametrics` | `0:0` |
| Screeps agents | `screeps-agent` | Outbound connections only | None | Image default |
| Room Planner | `room-planner` | [Tailscale HTTPS](https://room-planner.vulture-skink.ts.net/) | None | Image default |
| Radar | `radar` | [Tailscale HTTPS](https://radar.vulture-skink.ts.net/) | None | `65532:65532` |

Persistent applications use one replica, `Recreate`, and retained static `hostPath` PVs on the `/data` SSD. The K3s service requires that filesystem and verifies its UUID before startup. K3s state and container images live under `/var/lib/rancher/k3s` on the system disk. Declared PV capacities do not enforce disk quotas. The [nightly S3 backup](../shared/cluster/backups/README.md) ships suspended until setup is complete.

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

`apps-sync.yaml` reconciles Nanobot, Papra, monitoring, Screeps agents, Room Planner, and Radar together through `apps/kustomization.yaml`, matching Hetzner's layout. Tailscale readiness gates the whole group; application health is checked together with a 15-minute timeout. Monitoring and Screeps agents can start concurrently, so initial collection attempts can fail while backends start. Room Planner and Radar expose only Tailscale HTTPS ingresses and use no persistent storage.

Radar is a read-only trial using the upstream Helm chart. Tailscale access controls are its access gate; there is no separate application login. Anyone allowed to reach it can browse cluster resources, ConfigMaps, and pod logs. Pod exec, cluster changes, general Secret access, Cloud, and usage reporting are disabled; the Helm view is limited without Secret access. MCP is available read-only at `/mcp-readonly`. Timeline history is in memory and resets on pod restart.

Pod and node CPU/memory metrics come from K3s metrics-server. Optional Prometheus-backed workload charts are not configured: the existing VictoriaMetrics backend receives Screeps metrics, has no `up` series, and is rejected by Radar's automatic scrape-target check. No additional metrics collector is installed for this trial.

Versions and image digests live in manifests. Renovate proposes standard app and Helm chart updates, including digest updates for Room Planner's `latest` tag. Nanobot's [image workflow](images/nanobot/README.md) builds and tests custom images, then proposes the deployment digest. Only the custom Nanobot image is excluded from direct Renovate updates.

Both hosts share [host maintenance, Flux components, the Git source, and K3s upgrades](../shared/README.md). Repository-root `.sops.yaml` defines encryption rules for both hosts. Public Git, Nanobot, and Room Planner image pulls need no registry credentials.

- [Rebuild](docs/rebuild.md)
- [Maintenance, secrets, LAN access, and Screeps](docs/maintenance.md)
- [Tailscale authentication and Pi-hole DNS](docs/tailscale.md)
- [Nanobot Google Workspace OAuth](docs/google-workspace.md)
- [Room Planner image and access](docs/room-planner.md)
