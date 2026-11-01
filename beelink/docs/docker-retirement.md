# Docker retirement on Beelink

On 1 November 2026, the user requested stopping every Portainer/Docker
application except Hermes and Hindsight, and removing vmagent, cAdvisor,
Restic, and both old Nanobot containers.

## Current ownership

| Docker containers | State |
|---|---|
| hermes, hindsight | Running; original IDs, start times, restart policies and mounts preserved |
| portainer, room-planner | Stopped; restart policy `no` |
| grafana, loki, victoriametrics, papra | Retained stopped for rollback; restart policy `no`; active applications run in K3s |
| screeps-agent, screeps-agent-private | Retained stopped for rollback; restart policy `no`; active workers run in K3s |
| vmagent, cadvisor, restic-backup, nanobot, nanobot-api | Removed |

Portainer was stopped first, with restart disabled, so its Git polling cannot
recreate retired services. Its database and stack metadata remain at
`/data/portainer`; do not restart it or redeploy old stacks without reviewing
Kubernetes data ownership and obsolete service definitions. No separate host
Portainer/Restic service, timer, cron, or rc.local entry was found. Docker remains enabled to run
Hermes and Hindsight.

All cached named Docker images for repositories `selfhosted-restic-backup`,
`selfhosted-nanobot`, `victoriametrics/vmagent`, `ghcr.io/google/cadvisor`, and
`gcr.io/cadvisor/cadvisor` were removed without force. No global image, build
cache, network, or volume prune was performed. K3s uses containerd separately;
its Nanobot and monitoring images/workloads are unaffected.

The repository's Restic Compose definition and build/scripts/schedule were
deleted. vmagent, cAdvisor and the inline scrape config were removed from
`portainer/monitoring.yaml`; it retains only monitoring backend rollback
references. These collectors were not replaced in Kubernetes. Their dashboards
can still display retained history, but no new cAdvisor host/container data is
collected.

## Data and backups

No bind-mount contents, Docker volumes, K3s PV/PVC, or existing backup archives
were deleted. In particular, `/data/nanobot` remains mounted by Kubernetes.
Existing off-host Restic repositories and `/data/hermes-backup` native archives
remain intact. The Docker Restic scheduler is removed, so it no longer backs up
Portainer, Hermes archives, or Hindsight. K3s application backups remain disabled.

## Recovery implications

Nanobot's old Docker containers and local `selfhosted-nanobot` image are gone;
`docker start nanobot` is no longer a rollback path. Prefer the tested pinned
Kubernetes deployment. Any deliberate Docker recovery first requires suspending
Nanobot Flux, stopping all Kubernetes Nanobot writers, then reconstructing a
container/image from reviewed configuration against the retained data. Never
run both runtimes against `/data/nanobot`.

Room Planner is stopped rather than migrated. Its staged Flux Kustomization
remains suspended. Its former LAN URL on TCP 5173 is unavailable. Starting it
again requires an explicit choice to restore Docker or complete the separately
staged Kubernetes migration.

Other retained Docker containers can only be used after stopping their K3s
replacements; the [monitoring](monitoring.md), [Papra](papra.md), and
[Screeps](screeps-migration.md) runbooks describe ownership coordination.
The original private Screeps token still needs replacement; this retirement
does not fix its HTTP 401 error.

## Verification

Exactly two Docker containers remain running. All eight retained stopped
containers have restart policy `no`. Hermes and Hindsight have unchanged IDs,
start times, full container configuration, restart policies and mounts. Hermes
dashboard on TCP 9119 and Hindsight `/health` on TCP 8888 both returned HTTP 200;
Hindsight remains healthy. All 19 K3s pods retain their original UIDs, container
IDs and restart counts and remain Ready. The trimmed monitoring Compose file
validates and contains exactly Grafana, Loki and VictoriaMetrics.
