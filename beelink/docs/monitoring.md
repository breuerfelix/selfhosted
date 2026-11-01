# Monitoring on Beelink

Migration staged on 1 November 2026. Only Grafana, Loki, and single-node VictoriaMetrics move from Docker stack 26 into namespace `monitoring`; Flux manages plain manifests under `cluster/apps/monitoring`.

## Ownership and access

Do not start the old Docker backends while Kubernetes owns their directories. Monitoring uses static local PVs, prebound PVCs, empty storage class, `Retain`, Flux prune protection, and Recreate Deployments on node `beelink`. Namespace pruning is disabled too. PV capacities are binding declarations, not filesystem quotas. The existing K3s SSD UUID/mount startup guard remains required.

| Application | Host path | Pod path | UID:GID | URL |
|---|---|---|---|---|
| Grafana | `/data/grafana` | `/var/lib/grafana` | `0:0` | `https://grafana.vulture-skink.ts.net/` |
| Loki | `/data/loki` | `/loki` | `10001:10001` | `http://loki.monitoring.svc.cluster.local:3100` |
| VictoriaMetrics | `/data/victoriametrics` | `/data` | `0:0` | `http://victoriametrics.monitoring.svc.cluster.local:8428` |

Grafana has only Tailscale HTTPS ingress and a ClusterIP Service. Backends have only ClusterIP Services; no LAN ports, backend ingress, compatibility bridge, or built-in scraper. Future clients can use `/loki/api/v1/push` and `/api/v1/write` respectively.

Live inventory found five dashboards (`assets`, `beelink-cadvisor`, `google-health-overview`, `overview`, `victoriametrics-ops`), rather than the plan's older count of two. Data sources remain `loki` and `eezqmkxdueww0e` with their original short Service URLs. The retained plugin is `grafana-clock-panel` 2.1.9; startup plugin preinstallation is disabled. Grafana initialization credentials are SOPS-encrypted using the existing shared age recipient. The same immutable image and its unmodified default configuration preserve the existing encryption key; no custom security-key override was present. HTTPS root URL and secure session cookies are explicit.

Portainer automatic updates for shared stack 26 were disabled by the user without redeploying. Previous polling interval was 15 minutes, with no webhook. Keep them disabled. Never stop or redeploy the entire shared stack: cAdvisor and vmagent remain there. Both Screeps agents also remain unchanged. Their missing production telemetry is accepted until later migrations.

## Validation and recovery

Deployment and backup verification results will be recorded after cutover. Keep monitoring suspended until Docker writers have stopped and the stopped-writer recovery point is verified. Do not apply child workload manifests manually.

The existing Docker Restic include list excludes all three monitoring directories. This migration does not modify that backup job or establish ongoing monitoring backup coverage. Keep local recovery archives protected: Grafana state and container metadata contain credentials. A local backup is not protection against loss of the host.

## Rollback

1. Commit `suspend: true` in `beelink/cluster/monitoring-sync.yaml`, push, reconcile the root, and verify live monitoring suspension.
2. Scale only `monitoring/{grafana,loki,victoriametrics}` Deployments to zero. Wait until all their pods and container processes have exited. Retain namespace, PVs, PVCs, and data.
3. Delete only `monitoring/grafana` Ingress while reconciliation is suspended. Confirm its Tailscale proxy is gone.
4. Start only original Docker containers `victoriametrics`, `loki`, and `grafana`. Their immutable versions and original settings remain available. Restore their previous `unless-stopped` restart policies if Docker remains active owner. Keep Portainer updates disabled.
5. Verify historical backend queries and Grafana dashboards/credentials. Record active data ownership in Git before any future unsuspend. Restore the protected stopped-writer backup only if needed, with both runtimes stopped, preserving numeric ownership. Do not extract backups over a running application.

Interactive browser validation is a user step: sign in with existing credentials, open all five dashboards over Tailscale HTTPS, check data-source connections and Grafana Live/WebSocket behavior. Deferred-collector panels may have stale values.
