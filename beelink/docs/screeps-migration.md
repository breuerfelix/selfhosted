# Screeps agents on Beelink

Both agents moved from Docker/Portainer to Beelink K3s on 1 November 2026.
The public agent's real metrics and console logs are verified. The private
agent runs its preserved configuration but its original token is rejected with
HTTP 401; a valid private-server token is needed before ingestion can succeed.
Room Planner was explicitly deferred by the user and remains on Docker.

## Deployment

Namespace `screeps-agent` contains separate single-replica Deployments
`screeps-agent` and `screeps-agent-private`, both using Recreate. Flux
`screeps-agent` depends on the Ready `monitoring` Kustomization. Neither worker
has a Service, Ingress, published port, hostPort, hostNetwork, or persistent
storage. No PV/PVC or backup was created. cAdvisor, vmagent, Room Planner, and
unrelated applications were not migrated or restarted.

Both deployments use:

```text
ghcr.io/breuerfelix/screeps-agent@sha256:bb04e32ca6aedc447f9c85a360174024b3499d22f807e6fe16b8c19527a649fe
```

This is the original running registry index, not the current mutable `main`.
Its amd64 manifest is
`sha256:1d183f2fd7efdcd950e06c82f25995dd831882978cba5a94baa306eca486aa2a`.
The image config hash matches both original Docker images exactly:
`sha256:3239948eb289719f2e280f32983b2f5eaa5cae0613d088337d2d21ef1daff6b8`.
Source revision: `ba7e1c351ff72e28d17ab7017576fff9d6ce0520`.
The command remains `node agent.js`; anonymous registry pulls were verified.

Each SOPS-encrypted Secret preserves its own SCREEPS_TOKEN, SCREEPS_BASE_URL,
SCREEPS_SHARDS, TEST_MODE, and NODE_ENV. SOPS uses the existing Hetzner/Beelink
age recipient. A live pod-to-Docker comparison confirmed every original
effective environment value is unchanged except the two monitoring URLs.
Never print decrypted Secrets or raw Axios error objects, which may include
request credentials.

| Instance | Screeps base URL | Shards | Test mode |
|---|---|---|---|
| screeps-agent | https://screeps.com | shardSeason,shardX | false |
| screeps-agent-private | https://screeps.felixbreuer.me | coolify | false |

Monitoring base URLs are:

- `VICTORIA_METRICS_URL=http://victoriametrics.monitoring.svc.cluster.local:8428`
- `LOKI_URL=http://loki.monitoring.svc.cluster.local:3100`

The preserved application appends `/api/v1/import` for VictoriaMetrics
JSON-lines ingestion and `/loki/api/v1/push` for Loki. It does not use Prometheus
remote-write. Do not append endpoint paths to these environment variables.

Metric target labels remain `shard` (`shardSeason`, `shardX`, `coolify`), with
room/resource and other existing labels. Console logs retain
`source="screeps_console"`, `server_host`, `username`, `shard`, and
`message_type`. Server hosts distinguish public and private targets. Kubernetes
labels also have distinct `app.kubernetes.io/instance` values. No unsupported
application label variables or metric relabeling were introduced.

## Cutover evidence

The user disabled Portainer automatic updates. A read-only traversal of the
active committed Portainer database tree (transaction 317163) confirmed
`AutoUpdate: null` for stacks 20 and 22, including no polling/webhook settings.
No Portainer database or stack settings were changed by the migration agent.

Both original Docker workers were given restart policy `no` and stopped before
Flux was enabled. Containers and images remain available for rollback:

| Container | Docker ID | Exit time (UTC) |
|---|---|---|
| screeps-agent | aa94efdefa634e7f46d3b2f0825e7f911972acd51a27ec4c43daf581f5bd8422 | 2026-11-01 17:22:13.792 |
| screeps-agent-private | 92c5ad421f86adf5b9128db0b39c5c0a7a98a225b227458b928d9f1f9e30a772 | 2026-11-01 17:22:13.951 |

Kubernetes workers started at approximately 17:22:35 UTC, after both Docker
workers exited. There was no overlap. Their Flux enable commit is `367098c`.
Recreate stops the previous pod before starting its replacement on deployment
updates. Do not manually start retained Docker workers or a second collector.

## Functional validation

On 1 November 2026, after cutover:

- Both Deployments were 1/1 available with zero restarts and the expected image
  digest. Live Flux `screeps-agent` and its monitoring dependency were Ready.
- Secrets passed SOPS roundtrip checks and live effective environment equality.
  No Service, Ingress, or PVC exists in namespace `screeps-agent`.
- At 17:24 UTC, the public worker's first scheduled cycle ingested 314,496 real
  metric samples from 91 nonempty `shardX` segments and completed successfully.
  VictoriaMetrics queries returned 3,480 active `shardX` series with a latest
  source sample timestamp of 17:23:34.384 UTC, newer than pod startup.
- The same cycle fetched 91 `shardSeason` segments, all empty. No seasonal
  metrics were fabricated; the configured shard list remains unchanged.
- Loki queries restricted to timestamps after startup returned fresh real
  console records labeled `source="screeps_console"`,
  `server_host="screeps.com"`, `username="fbr"`, `shard="shardX"`, and
  `message_type="log"`. Worker logs confirmed successful forwarding. No
  public-worker authentication or monitoring connection errors were observed.
- The private pod reached `/api/version` over HTTPS and received HTTP 200,
  resolving the earlier pod connectivity concern. With its unchanged token,
  both `/api/auth/me` and `/api/user/memory-segment` returned HTTP 401 with
  `unauthorized`. Its scheduled collection failed with HTTP 401 and the console
  streamer exited with HTTP 401. No fresh private metrics/log ingestion is
  claimed; no synthetic records were used as substitutes.

Earlier Mac/Beelink HTTPS timeouts were acknowledged by the user as a network
issue they will fix. No Hetzner firewall, server, or authentication configuration
was changed. Network repair alone does not resolve the private pod's observed
HTTP 401.

Both workers have no browser-facing URL. Monitoring UI remains
<https://grafana.vulture-skink.ts.net/>; no new ingress or browser action is
needed for the agent migration.

## Remaining private-token action

Provide a valid token for the existing private server in a protected local file
(mode 0600), for example `temp/screeps-migration/private-screeps-token`. Do not
paste it into chat. Replace only `SCREEPS_TOKEN` in
`cluster/apps/screeps-agent/screeps-agent-private-env.sops.yaml` through SOPS;
keep all other settings and the image pin. Commit/push, reconcile Flux, then
restart only Deployment `screeps-agent-private` using its Recreate strategy.
A Secret update alone does not restart a pod using envFrom.

The preserved application exits its console streaming task after an initial
identity/authentication failure; it does not retry that initial failure. After
credential/network recovery, restart that private Deployment, then verify both
a successful scheduled collection and fresh Loki records with
`server_host="screeps.felixbreuer.me"`, `shard="coolify"` and the expected
username. Check fresh `coolify` metrics in VictoriaMetrics. Do not mark private
ingestion verified based only on pod readiness.

## Rollback

1. Set `suspend: true` in `cluster/screeps-agent-sync.yaml`, commit/push, reconcile
   root Flux, and verify the live `screeps-agent` Kustomization is suspended.
2. Scale only Deployments `screeps-agent` and `screeps-agent-private` in namespace
   `screeps-agent` to zero. Wait for all their pods and processes to exit.
3. Start only the two retained Docker agents and restore their original `always`
   restart policies. Keep Portainer stacks 20/22 automatic updates disabled.

   ```bash
   ssh bee 'docker update --restart=always screeps-agent screeps-agent-private && docker start screeps-agent screeps-agent-private'
   ```

4. Keep Flux suspended while Docker runs. No data restore is needed. The old
   Docker monitoring URLs use retired Docker service names; restoring containers
   alone does not restore monitoring ingestion. Their endpoints must be made
   reachable separately. Do not restart unrelated retired monitoring containers.
   The original private token will still fail if its server rejects it.

## Deferred Room Planner staging

Room Planner remains running on Docker at <http://192.168.178.13:5173/>. Its
Docker lifecycle and restart policy are unchanged. Its Flux Kustomization stays
suspended; no Room Planner namespace, pod, Service, Ingress, PV/PVC, tailnet
device, or certificate was created. Do not unsuspend it as part of agent work.
The proposed <https://room-planner.vulture-skink.ts.net/> is not active.

The prior staging investigation found the live local image
`room-planner-room-planner` matches source
`be8ef67405493a1d1ecdfb9d93cc26eb2db0d7aa`, except its generated lockfile.
The Compose full-SHA tag is not the running version; CI published the short tag
`sha-6e80add` for newer source. A preserving build was prepared on source branch
`codex/k3s-room-planner`, commit `520f2c73cb2d94ee6587d0c75cee2779d556d8c8`,
with the original Node base digest and captured frozen dependency lockfile.
[Build 41329440344](https://github.com/breuerfelix/screeps-room-planner/actions/runs/41329440344)
passed UI/same-origin proxy smoke tests and published private image
`ghcr.io/breuerfelix/screeps-room-planner@sha256:eaf7c898d6dc7bfba9389062490673663e2887ac725e2209672d6d53f7d0b635`.
See [provenance and rebuild instructions](../images/room-planner/README.md).
The staged frontend uses `/plan` on the same origin; internal proxy URL remains
`http://127.0.0.1:3001` and SCREEPS_LOCAL_SERVER_URL remains
`https://screeps.felixbreuer.me`. A SOPS-encrypted GHCR imagePullSecret and actual
HTTPS/UI/proxy checks would still be required for any separately authorized
future migration. No registry credential is needed for the completed agent
cutover.
