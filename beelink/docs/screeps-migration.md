# Room Planner and Screeps agents on Beelink

Migration staged on 1 November 2026. Keep Flux suspended until each old
Portainer stack has automatic redeployment disabled and the selected Docker
containers are stopped with restart policy `no`. Retain containers for rollback.
No persistent mounts exist; this migration creates no PV/PVC and no backups.
Do not operate cAdvisor, vmagent, or unrelated stacks.

## Agents

Namespace `screeps-agent` contains separate single-replica Deployments
`screeps-agent` and `screeps-agent-private`, both using Recreate. No Service,
Ingress, published port, hostPort, hostNetwork, or storage is needed. Flux
`screeps-agent` depends on the Ready `monitoring` Kustomization.

Both original containers use registry index
`ghcr.io/breuerfelix/screeps-agent@sha256:bb04e32ca6aedc447f9c85a360174024b3499d22f807e6fe16b8c19527a649fe`.
Its amd64 manifest is
`sha256:1d183f2fd7efdcd950e06c82f25995dd831882978cba5a94baa306eca486aa2a`;
its image config matches the running Docker image exactly:
`sha256:3239948eb289719f2e280f32983b2f5eaa5cae0613d088337d2d21ef1daff6b8`.
Source revision: `ba7e1c351ff72e28d17ab7017576fff9d6ce0520`.
The registry permits anonymous pulls. The command remains `node agent.js`.

Each encrypted environment Secret preserves its own SCREEPS_TOKEN,
SCREEPS_BASE_URL, SCREEPS_SHARDS, TEST_MODE, and NODE_ENV from Docker.
SOPS uses the existing Hetzner/Beelink age recipient. Do not print decrypted
Secrets or raw agent errors: Axios errors can include request credentials.

| Instance | Screeps base URL | Shards | Test mode |
|---|---|---|---|
| screeps-agent | https://screeps.com | shardSeason,shardX | false |
| screeps-agent-private | https://screeps.felixbreuer.me | coolify | false |

Only the two monitoring base URLs change:

- `VICTORIA_METRICS_URL=http://victoriametrics.monitoring.svc.cluster.local:8428`
- `LOKI_URL=http://loki.monitoring.svc.cluster.local:3100`

Source inspection confirms the application appends `/api/v1/import` for
VictoriaMetrics JSON-lines ingestion and `/loki/api/v1/push` for Loki.
It does not use Prometheus remote-write. Do not append paths to these env vars.

Existing metric labels use `shard` (`shardSeason`, `shardX`, `coolify`), with
room/resource and other application labels. Console logs retain
`source="screeps_console"`, `server_host`, `username`, `shard`, and
`message_type`; the two `server_host` values distinguish targets. Deployment
labels also retain distinct `app.kubernetes.io/instance` values. The original
agent does not read an INSTANCE_LABEL variable; none is invented here.

Before migration, Docker agents could no longer resolve the stopped Docker
monitoring backends. The private Screeps HTTPS origin also timed out from both
Beelink and the Mac; verify its reachability separately from cluster readiness.

## Room Planner provenance

The running local Docker image is `room-planner-room-planner`, config
`sha256:0ece0cd9f7dcf02acfedfbc7507b3c3ad8d1a31f923cd824d1e21c13fc0b1f2d`.
It has no registry digest. All 381 compared tracked source/build files match
upstream `be8ef67405493a1d1ecdfb9d93cc26eb2db0d7aa`, except the generated
`yarn.lock`. The repository Compose reference to
`sha-6e80addde9eab3b90411be4d0865ded7a79500da` is not the running version;
CI actually published the short tag `sha-6e80add`, and that newer source changes
runtime code and development dependencies. It is not used for this migration.

The private source repository branch `codex/k3s-room-planner` starts at the
matching old revision and changes only its image workflow, Dockerfile, and
lockfile captured from the live image. The original Node 22.23.2 base digest
`sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436`
matches all five original base layer diff IDs. The build uses Yarn 1.22.22 with
`--frozen-lockfile`, pinned GitHub Actions following this repository's nanobot
conventions, linux/amd64, and an isolated UI/proxy smoke test before publishing.
The private GHCR package stays private.

The frontend builds with `VITE_ROOM_PLANNER_API_BASE_URL=/plan`. Its fetch is
same-origin; Vite preview proxies `/plan`, `/terrain`, and `/room-objects` to
`ROOM_PLANNER_PROXY_URL=http://127.0.0.1:3001` inside the same container.
PORT remains 3001 and SCREEPS_LOCAL_SERVER_URL remains
`https://screeps.felixbreuer.me`. The UI listens on 5173. Client requests must
use the Tailscale HTTPS origin, never client localhost or cluster DNS.

## Cutover and rollback

Disable automatic Portainer Git updates for stacks 17, 20, and 22 before stopping
anything. Verify stack settings through the API. Set restart policy `no` and
stop only `room-planner`, `screeps-agent`, and `screeps-agent-private`; verify
all three exited before committing `suspend: false` and reconciling Flux.
Keep stopped containers and their immutable images.

For rollback:

1. Commit/push `suspend: true` for `room-planner-sync.yaml` and
   `screeps-agent-sync.yaml`, reconcile root Flux, and verify suspension.
2. Scale the three Kubernetes Deployments to zero. Wait for all their pods and
   container processes to exit before starting any Docker worker.
3. Delete only the Room Planner Ingress while its Flux resource is suspended;
   wait for its Tailscale proxy to disappear.
4. Start only the three retained Docker containers and restore their original
   `unless-stopped` restart policies. Keep Portainer automatic updates disabled.
   Room Planner's original URL is `http://192.168.178.13:5173/`.
5. Docker agent monitoring URLs still use retired Docker DNS names; a rollback
   needs reachable monitoring endpoints to restore ingestion. Do not restart
   unrelated old monitoring containers or change collectors as part of rollback.

Recreate prevents rolling-update overlap. Never manually start a second copy,
force-delete a worker pod, or start a retained Docker agent while K3s owns it.

## Validation still required before completion

Verify pinned image pulls and live Flux state, original env equality (without
printing credentials), HTTPS chain/hostname, UI JS assets, same-origin proxy GET
and actual POST /plan. Check fresh real metrics for each configured shard and
fresh real console logs with target-specific server_host labels, and inspect
sanitized worker errors. A Running pod is not evidence of successful ingestion.
Browser operation is outside this migration: the user must open the HTTPS UI,
choose a room, run planning, and confirm the map renders and browser requests
stay on the HTTPS origin.
