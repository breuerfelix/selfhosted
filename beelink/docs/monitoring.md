# Monitoring on Beelink

Migration executed on 1 November 2026. Only Grafana, Loki, and single-node VictoriaMetrics move from Docker stack 26 into namespace `monitoring`; Flux manages plain manifests under `cluster/apps/monitoring`.

## Ownership and access

Do not start the old Docker backends while Kubernetes owns their directories. Monitoring uses static local PVs, prebound PVCs, empty storage class, `Retain`, Flux prune protection, and Recreate Deployments on node `beelink`. Namespace pruning is disabled too. PV capacities are binding declarations, not filesystem quotas. The existing K3s SSD UUID/mount startup guard remains required.

| Application | Host path | Pod path | UID:GID | URL |
|---|---|---|---|---|
| Grafana | `/data/grafana` | `/var/lib/grafana` | `0:0` | `https://grafana.vulture-skink.ts.net/` |
| Loki | `/data/loki` | `/loki` | `10001:10001` | `http://loki.monitoring.svc.cluster.local:3100` |
| VictoriaMetrics | `/data/victoriametrics` | `/data` | `0:0` | `http://victoriametrics.monitoring.svc.cluster.local:8428` |

Grafana has only Tailscale HTTPS ingress and a ClusterIP Service. Backends have only ClusterIP Services; no LAN ports, backend ingress, compatibility bridge, or built-in scraper. Future clients can use `/loki/api/v1/push` and `/api/v1/write` respectively.

Live inventory found five dashboards (`assets`, `beelink-cadvisor`, `google-health-overview`, `overview`, `victoriametrics-ops`), rather than the plan's older count of two. Data sources remain `loki` and `eezqmkxdueww0e` with their original short Service URLs. The retained plugin is `grafana-clock-panel` 2.1.9; startup plugin preinstallation is disabled. Grafana initialization credentials are SOPS-encrypted using the existing shared age recipient. The same immutable image and its unmodified default configuration preserve the existing encryption key; no custom security-key override was present. HTTPS root URL and secure session cookies are explicit.

Portainer automatic updates for shared stack 26 were disabled by the user without redeploying. Previous polling interval was 15 minutes, with no webhook. Keep them disabled. cAdvisor and vmagent were subsequently removed at the user's request; they have no replacement collector. Both Screeps agents now run separately in K3s. Portainer is stopped with restart disabled; see [Docker retirement](docker-retirement.md).

## Validation and recovery

Flux `monitoring` is enabled and Ready. All three applications run with one Ready pod and zero restarts. Original Docker containers `grafana`, `loki`, and `victoriametrics` exited cleanly with code 0 and remain stopped with `restart=no`. No Kubernetes writer started before backup verification; recovery-test containers used separate restored directories and were removed afterward.

Verified on 1 November 2026:

- All three retained PVs/PVCs are Bound. Runtime mount information confirms ext4 `/dev/nvme0n1` subdirectories `/grafana`, `/loki`, and `/victoriametrics` at the required container paths. Actual process UID/GID and host directory ownership match the table above.
- Loki WAL checkpoint/segment recovery completed with `errors=false`. Historical metrics from the previous day and five historical log entries match the pre-cutover API responses exactly, both in independent recovery copies and in the deployed applications.
- All five Grafana dashboard JSON definitions and both complete data-source API definitions match baseline. Database comparisons confirm user/password records and encrypted data-source credential records are unchanged. Both data-source health APIs report `OK`; clock plugin 2.1.9 is registered.
- From the Mac, HTTPS certificate verification passed, unauthenticated access redirected to login, existing credentials authenticated successfully, the authenticated page returned 200, and the session cookie had Secure/HttpOnly attributes. Grafana Live completed an authenticated same-origin WebSocket upgrade with HTTP 101. The explicit HTTPS root URL supplies the origin expected by [Grafana Live](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-grafana-live/).
- A temporary unprivileged client in namespace `default` resolved both fully qualified backend Service names, sent a real Snappy/protobuf Prometheus remote-write request and Loki JSON push (both HTTP 204), and read both records back. Its synthetic labels include `migration_id="monitoring-migration-20261101"` and `source_namespace="default"`. The test pod was deleted. The first attempt preceded Loki readiness; it was repeated successfully after all pods became Ready.
- No listeners remain on host ports 3000, 3001, 3100, or 8428. The former published LAN ports 3001/3100/8428 were unreachable from the Mac. Monitoring Services are ClusterIP only; only Grafana has an Ingress/Tailscale proxy.
- cAdvisor, vmagent, both Screeps agents, and every other retained Docker container have unchanged IDs, start times, running states, and restart policies. Nanobot HTTPS returned 200 with certificate verification and its pod remained Ready. The user intentionally removed unrelated `cloudflared` and the previously stopped Docker `tailscale` container during this work; this migration did not operate on them.

Recovery artifacts on `ssh bee`:

```text
/var/backups/monitoring-migration-20261101/
  data.tar                          # 79,739,463,680 bytes; all three data trees
  data.tar.sha256
  docker-original.json              # original images, settings, mounts, environment
  loki-config.yaml
  baseline.json
  backup-verified.json
  restore-verified.json
  grafana-preservation-sha256.json
```

The directory is root-only (0700); archive, metadata, and credential-bearing records are 0600. Non-secret Loki config is 0644 inside that protected directory. Archive SHA-256 is `a2f59b250a7097dc4977f9151f1a9e5157dd66baca6d6e81205b20632c380d19`. All writers were stopped before archiving. Full archive/source byte comparison passed; full extraction passed; recovered Grafana SQLite `integrity_check` returned `ok`; all three recovered applications started with the original immutable Docker images in isolated network namespaces. Recovered historical metric/log responses matched baseline exactly. Generated 74 GiB recovery-test copies were removed after success; the archive remains on the internal system disk, separate from the data SSD.

For restore, first stop both runtimes, verify `sha256sum -c data.tar.sha256`, and extract into clean application paths using GNU tar with `--acls --xattrs --numeric-owner -xpf data.tar -C /data`. Preserve existing directories separately until recovery succeeds; do not overlay a running or populated dataset. Normal rollback reuses current data and requires no restore. Never apply child workload manifests manually while suspended.

The migration did not establish ongoing monitoring backup coverage. The Docker Restic job was subsequently removed at the user's request. Keep local recovery archives protected: Grafana state and container metadata contain credentials. A local backup is not protection against loss of the host.

## Rollback

1. Commit `suspend: true` in `beelink/cluster/monitoring-sync.yaml`, push, reconcile the root, and verify live monitoring suspension.
2. Scale only `monitoring/{grafana,loki,victoriametrics}` Deployments to zero. Wait until all their pods and container processes have exited. Retain namespace, PVs, PVCs, and data.
3. Delete only `monitoring/grafana` Ingress while reconciliation is suspended. Confirm its Tailscale proxy is gone.
4. Start only original Docker containers `victoriametrics`, `loki`, and `grafana`. Their immutable versions and original settings remain available. Restore their previous `unless-stopped` restart policies if Docker remains active owner. Keep Portainer updates disabled.
5. Verify historical backend queries and Grafana dashboards/credentials. Record active data ownership in Git before any future unsuspend. Restore the protected stopped-writer backup only if needed, with both runtimes stopped, preserving numeric ownership. Do not extract backups over a running application.

Interactive browser validation is a user step: sign in with existing credentials, open all five dashboards over Tailscale HTTPS, check data-source connections and Grafana Live/WebSocket behavior. Retired-collector panels show historical data only.
