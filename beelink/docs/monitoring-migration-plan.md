# Monitoring migration to K3s

Plan only. Live inventory verified on 1 November 2026 through `ssh bee`. Scope revised at the user's request: migrate only Grafana, Loki, and VictoriaMetrics. No deployment changes made.

## Target and scope

Run Grafana, single-node VictoriaMetrics, and single-binary Loki in namespace `monitoring`. Manage manifests with Flux under `beelink/`, encrypt secrets with the existing Hetzner/Beelink SOPS age key, and reuse each existing persistent host directory without moving data.

Grafana gets Tailscale HTTPS ingress only. Loki and VictoriaMetrics get ClusterIP Services accessible to Grafana and future applications across namespaces. Preserve current data, Grafana users/dashboards/data-source UIDs, Loki schema, and image versions during cutover.

Explicitly deferred:

- cAdvisor and vmagent migration, replacement, reconfiguration, shutdown, or retirement.
- Screeps agent migration, telemetry URL changes, and Docker-to-Kubernetes compatibility bridges.
- Scrape configuration, VictoriaMetrics built-in scraping, and automatic log collection.
- Grafana LAN exposure, ServiceLB resources, and fixed Service IP reservations.

Existing Docker collectors and Screeps agents may lose telemetry connectivity after the backends move. This interruption is accepted and does not block migration or trigger rollback. Dashboard definitions and history must survive; current collector-dependent panels may show no fresh data until those components migrate later.

## Verified inventory

| Component | Running image | Existing host mount → container mount | Data size | Current Docker host port |
|---|---|---|---|---|
| Grafana | `grafana/grafana:13.2.4` | `/data/grafana` → `/var/lib/grafana` | 504 MiB | TCP 3001 → 3000 |
| VictoriaMetrics | `victoriametrics/victoria-metrics:v1.154.0` | `/data/victoriametrics` → `/data` | 74 GiB | TCP 8428 |
| Loki | `grafana/loki:3.7.8` | `/data/loki` → `/loki` | 44 MiB | TCP 3100 |

These three containers belong to Portainer stack `monitoring` (26), network `monitoring_monitoring`, and currently use `restart: unless-stopped`. The same stack also contains cAdvisor and vmagent; operate on the three selected containers individually, not a whole-stack stop/redeploy. The old configuration is in `portainer/monitoring.yaml`; live containers establish migration versions and settings.

The SSD is mounted at `/data`, ext4 UUID `3da917f6-a469-43f4-831a-5a9eef982cd5`. The existing K3s mount/UUID startup guard stays in place. Approximately 1.6 TiB is free.

Grafana runs as UID 0 with directory ownership `0:0`. Loki runs as UID 10001 with directory ownership `10001:10001`. VictoriaMetrics runs as root with directory ownership `0:0`. Keep these effective identities initially; do not recursively chown data during migration.

Grafana's SQLite database contains two dashboards and these data sources:

| Name | UID | Type | URL |
|---|---|---|---|
| VictoriaMetrics | `eezqmkxdueww0e` | `prometheus` | `http://victoriametrics:8428` |
| Loki | `loki` | `loki` | `http://loki:3100` |

Matching Kubernetes Service names in the same namespace preserve both URLs without editing Grafana's database. The installed `grafana-clock-panel` is version `2.1.9`.

## Workloads and storage

- One Deployment per application, one replica, `strategy: Recreate`. Give each an explicitly bound static local PV/PVC, empty storage class, node affinity `kubernetes.io/hostname: beelink`, reclaim policy `Retain`, and Flux prune protection on both PV and PVC. Protect the namespace from accidental Flux pruning too. PVs are cluster-scoped; application resources and PVCs belong to `monitoring`.
- Mount precisely the paths in the inventory. Require directories to exist; no `DirectoryOrCreate`, fresh data paths, database import, or storage provisioner. PV capacity declarations do not impose filesystem quotas on these shared-SSD directories.
- Pin current images by tag and matching live registry digest. Preserve entrypoints, effective UID/GID, retention, and application configuration. Add startup/readiness probes and graceful shutdown timeouts; allow Loki WAL replay and VictoriaMetrics data startup without premature liveness restarts.
- Use a ConfigMap for Loki configuration. Put necessary Grafana credentials in a SOPS-encrypted Secret using the existing recipient. Preserve any effective Grafana encryption secret; do not silently generate a replacement. Existing administrator credentials live in the retained database; environment initialization credentials do not reset that account.
- Keep Grafana analytics/update checks disabled and preserve its installed clock plugin version. Validate plugin startup without opportunistic plugin upgrades. Do not add dashboard/data-source provisioning that overwrites existing runtime state.
- Keep VictoriaMetrics arguments `-storageDataPath=/data`, `-retentionPeriod=10y`, and `-httpListenAddr=:8428`. Do not add `-promscrape.config`; collection is deferred.
- Store Loki's current configuration explicitly, preserving `auth_enabled: false`, TSDB/filesystem schema `v13`, schema start date `2020-10-24`, 24-hour indexes, replication factor 1, and in-memory ring. Effective WAL, active index, index cache, chunks, compactor, and temporary rules paths already sit under `/loki`; all remain on `/data/loki`.

Use plain manifests for these three applications. No additional monitoring operator, chart, collector, or ingress controller is needed.

## Services and exposure

| Service / route | Destination | Access |
|---|---|---|
| `grafana` ClusterIP, port 80 | Grafana container TCP 3000 | Cluster and Tailscale ingress backend |
| Tailscale ingress `grafana` | `grafana:80` | Proposed `https://grafana.vulture-skink.ts.net/` |
| `loki` ClusterIP, port 3100 | Loki TCP 3100 | Internal service clients |
| `victoriametrics` ClusterIP, port 8428 | VictoriaMetrics TCP 8428 | Internal service clients |

Confirm the Tailscale hostname is unused before creation. Use the existing operator, `ingressClassName: tailscale`, and `tls.hosts: [grafana]`. Keep Grafana authentication enabled and validate login, redirects, cookies, dashboard loading, and Grafana Live over HTTPS. Preserve existing server settings unless the ingress requires a specific adjustment.

None of the three applications gets a LoadBalancer, NodePort, hostPort, or hostNetwork. Only Grafana gets an Ingress. The old Docker host ports 3001, 3100, and 8428 disappear after cutover; no replacement LAN listeners are created. Existing ServiceLB configuration for other applications stays unchanged.

Allow Kubernetes to allocate ordinary ClusterIPs; no fixed addresses or Docker compatibility configuration. ClusterIP addressing is not an authentication boundary. Preserve access for trusted applications across namespaces rather than introducing a same-namespace-only NetworkPolicy.

Future applications use:

```text
VictoriaMetrics remote_write:
http://victoriametrics.monitoring.svc.cluster.local:8428/api/v1/write

Loki log push:
http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
```

These Services provide ingestion endpoints; deploying the backends does not automatically collect application metrics or pod logs. Client/collector setup will happen in later migrations. [VictoriaMetrics ingestion](https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/), [Loki push API](https://grafana.com/docs/loki/latest/reference/loki-http-api/).

## Proposed repository layout

```text
beelink/cluster/monitoring-sync.yaml
beelink/cluster/apps/monitoring/
  kustomization.yaml
  namespace.yaml
  grafana/          # Deployment, ClusterIP, retained storage, encrypted env,
                   # Tailscale ingress
  loki/            # Deployment, ClusterIP, retained storage, explicit config
  victoriametrics/ # Deployment, ClusterIP, retained storage
beelink/docs/monitoring-migration-plan.md
beelink/docs/monitoring.md             # Runbook/status after implementation
```

Use one Flux `monitoring` Kustomization, initially `suspend: true`, depending on `tailscale`, with `wait: true`, a suitable startup timeout, and existing `sops-age` decryption. Add its sync file to the cluster root. Publish and review the suspended configuration while Docker still owns the data. Do not apply child workload manifests manually while suspended.

## Execution sequence after approval

1. **Prepare and validate.** Recheck mounts/UUID, live versions/configuration, and Tailscale hostname. Capture baseline dashboard/data-source IDs, historical metric/log queries, and unrelated container IDs/start times. Verify the user's existing monitoring backups and recovery method: the repository's current Docker Restic include list does not cover these three directories. Do not treat a live filesystem copy as a consistent database backup.
2. **Publish inactive manifests.** Create files and SOPS Secret, pin live image digests, render Kustomize, validate schemas/configuration and server-side dry-runs as applicable, and publish the suspended Flux sync. Pre-pull pinned images if useful. No Kubernetes writer starts yet.
3. **Prevent Docker recreation.** Disable Portainer automatic redeploy for shared stack 26 so it cannot recreate the three old writers. The user handles required browser steps. Save current settings for rollback, then set only Docker Grafana, Loki, and VictoriaMetrics to `restart=no`. Leave cAdvisor, vmagent, and both Screeps agents unchanged. Do not redeploy or stop the whole shared stack.
4. **Stop the three writers cleanly.** Stop only Grafana, Loki, and VictoriaMetrics gracefully, allowing at least 120 seconds for stateful services and verifying exit rather than forcing termination. Confirm no remaining process writes their three data directories. Do not drain, stop, or reconfigure vmagent or other producers; their failed telemetry during this interval is accepted.
5. **Establish recovery point.** With writers stopped, verify or create consistent recoverable backups/snapshots of the three applications. VictoriaMetrics has 74 GiB: reuse its directory directly; do not copy that dataset as a migration mechanism. Record recovery artifacts and protect credentials they contain. Never start Docker and Kubernetes against the same directory together; `ReadWriteOnce` does not exclude Docker writers.
6. **Start Kubernetes.** Unsuspend monitoring in Git and reconcile Flux. Check all PVC bindings, actual mount paths/UIDs, Loki replay, backend readiness, Grafana startup, and Tailscale proxy/certificate. No data restore or directory rename should be needed.
7. **Verify preservation and access.** Query historical metrics and logs, verify the two dashboard definitions, existing data-source UIDs, and plugin. Test backend DNS and ingestion from another Kubernetes namespace with a small uniquely labelled synthetic metric/log, then remove the temporary test pod. Validate Grafana HTTPS from the Mac with certificate verification; the user handles interactive browser login/dashboard checks. Verify no application LAN listeners or Loki/VictoriaMetrics Tailscale exposure. Confirm unrelated Docker containers and nanobot remain healthy. Existing collector health, new production telemetry, and fresh values in collector-dependent panels are not acceptance requirements.
8. **Record completion.** Keep the three old Docker containers stopped with restart disabled for rollback. Mark those services retired in the old Portainer definition without redeploying the deferred collectors or producers. Record deferred telemetry work and backup coverage in the runbook. Do not delete SSD data or the shared Docker network.

## Rollback

1. Suspend monitoring reconciliation in Git and confirm live suspension. Scale the three Kubernetes Deployments to zero and verify no writer remains. Do not delete namespace, PVs, PVCs, or data.
2. Disable the new Grafana ingress while reconciliation is suspended. There is no Grafana LAN Service or ServiceLB port to remove.
3. Restart only the original Docker VictoriaMetrics, Loki, and Grafana with their original configuration and images. Restore their restart policies if Docker remains the active owner. Reusing the same pinned versions avoids a version downgrade/data-format change. Docker restores its original host-port mappings.
4. Verify Grafana history and backend health. Leave cAdvisor, vmagent, and Screeps configuration unchanged; restoring their telemetry is not a separate migration step. Keep Portainer automatic redeploy disabled until rollback state is understood.
5. Record suspended resources and active ownership in Git before any future unsuspend. Do not let Flux recreate Kubernetes writers while Docker owns the directories.

## Acceptance

- Exactly Grafana, Loki, and VictoriaMetrics are migrated into `monitoring` through Flux; secrets use the existing SOPS key.
- Original three SSD directories and effective ownership remain intact; history, dashboards, credentials, data-source UIDs, and Loki WAL/index data survive.
- Grafana works through its Tailscale HTTPS ingress. None of the three applications has a LAN-published port.
- Loki and VictoriaMetrics expose internal Services; a cross-namespace Kubernetes client can ingest successfully.
- cAdvisor, vmagent, and Screeps agents remain outside this migration. Missing telemetry from them is accepted until later work.
- Exactly one runtime owns each persistent directory, with a verified recovery point and documented rollback.
