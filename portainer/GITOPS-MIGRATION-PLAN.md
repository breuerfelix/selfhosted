# GitOps migration plan for `breuerfelix/selfhosted`

This plan turns `breuerfelix/selfhosted` into the deployment source of truth for the committed Portainer inventory and the now compose-based Coolify application definitions, with honest downtime expectations per workload.

Scope of the committed repo state used for this plan update:
- Portainer endpoint `local` (`endpoint_id: 3`) with 4 stacks: `immich`, `dawarich`, `monitoring`, `room-planner`
- Coolify project `default` on server `localhost` / `host.docker.internal` with 7 applications now represented on `main` as `coolify/applications/<app>/docker-compose.yaml`: `danielkueffler`, `fathom`, `idle-proxy`, `noobgallery`, `redirect-breuer-dev`, `screeps`, `travian-inactive-finder`
- Legacy Kubernetes-era manifests preserved under `deprecated/`

Merged state reflected here:
- PR #69 (`4ed81ac`) replaced the earlier Coolify JSON export snapshot on `main` with per-app Docker Compose YAML manifests.
- Deployment remains pending and out of scope. This document update does not apply, deploy, or reconcile anything to Portainer or Coolify.

## 1. What the repo tells us today

### Portainer inventory already committed

| Workload | Entrypoint | Published ports | Persistent data from compose | Current Git-backed? | Downtime expectation for GitOps cutover |
| --- | --- | --- | --- | --- | --- |
| `dawarich` | `docker-compose.yml` | `3000:3000` | `/data/dawarich/redis`, `/data/dawarich/db`, `/data/dawarich/public`, `/data/dawarich/watched`, `/data/dawarich/storage` | No | Zero downtime not realistic with current single DB/data mounts and direct host port. Plan for short maintenance window. |
| `immich` | `docker-compose.yml` | `2283:2283` | `${UPLOAD_LOCATION}`, `${DB_DATA_LOCATION}`, `model-cache` | No | Zero downtime not realistic with current single Postgres data dir and direct host port. Plan for short maintenance window. |
| `monitoring` | `docker-compose.yml` | `3001:3000`, `8428:8428` | `/data/grafana`, `/data/victoriametrics` | No | Keep until last. Brief interruption likely required unless storage and traffic are re-architected first. |
| `room-planner` | `docker-compose.portainer.yml` | `${ROOM_PLANNER_UI_PORT:-5173}:5173` | none declared in compose | Yes, but from `breuerfelix/screeps-room-planner` | Near-zero downtime is realistic if migrated to immutable image + staged port/proxy cutover. |

Important observations from the Portainer export:
- `room-planner` is the only stack already linked to Git, and it points to `https://github.com/breuerfelix/screeps-room-planner.git`, not this repo.
- The three other stacks are not Git-backed yet.
- `immich`, `dawarich`, and `monitoring` publish host ports directly. Without a front proxy or temporary port indirection, true blue/green on the same host is not possible because two stacks cannot bind the same host port at once.
- `monitoring` is the observability stack. Migrating it early would remove visibility during later cutovers.

### Coolify compose manifests now committed

| Application | Compose path | FQDN | Image | Known repo gaps | Likely statefulness | Downtime expectation for GitOps cutover |
| --- | --- | --- | --- | --- | --- | --- |
| `redirect-breuer-dev` | `coolify/applications/redirect-breuer-dev/docker-compose.yaml` | `https://felixbreuer.me` | `grahamdigital/simple-redirect:latest` | `PROTOCOL` / `REDIRECT_TO` still redacted; no health check encoded yet | Stateless | Zero/near-zero realistic via duplicate app + domain switch. |
| `idle-proxy` | `coolify/applications/idle-proxy/docker-compose.yaml` | `https://idle-proxy.felixbreuer.me` | `ghcr.io/breuerfelix/idle-mmo-extensions/idle-proxy:latest` | No env keys committed; health check still needs to be added explicitly | Stateless | Zero/near-zero realistic via duplicate app + domain switch. |
| `noobgallery` | `coolify/applications/noobgallery/docker-compose.yaml` | `https://photos.felixbreuer.me` | `felixbreuer/noobgallery:latest` | Storage semantics still unverified in repo; health check missing | Probably stateless or externally stateful; verify first | Usually near-zero if storage is external or read-only. |
| `travian-inactive-finder` | `coolify/applications/travian-inactive-finder/docker-compose.yaml` | `https://inactive-finder.felixbreuer.me` | `felixbreuer/travian-inactive-finder:latest` | No env keys committed; health check still needs to be added explicitly | Likely stateless | Zero/near-zero realistic via duplicate app + domain switch. |
| `danielkueffler` | `coolify/applications/danielkueffler/docker-compose.yaml` | `https://danielkueffler.de` | `ghost:5-alpine` | Local Ghost volume captured, but redacted/live envs and operational checks still need confirmation | Stateful (`database__connection__filename` points at local Ghost content) | True zero downtime unlikely unless storage is externalized first. |
| `fathom` | `coolify/applications/fathom/docker-compose.yaml` | `https://stats.felixbreuer.me` | `usefathom/fathom:version-1.2.1` | Legacy volume hint carried over, but DB/storage semantics and health checks still need confirmation | Stateful or semi-stateful | Treat as minimal-downtime until DB/storage is confirmed. |
| `screeps` | `coolify/applications/screeps/docker-compose.yaml` | `https://screeps.felixbreuer.me` | `screepers/screeps-launcher:latest` | `screeps-data` hint is only partial evidence; world-state handling and backups still need confirmation | Stateful/high-risk | Do not promise zero downtime until storage mapping and world-state handling are confirmed. |

Important observations from the current Coolify repo state:
- PR #69 merged a compose-based GitOps baseline into `main`; the raw `applications.json`, `app.json`, and `envs.redacted.json` snapshot files are no longer the primary committed representation.
- The committed `docker-compose.yaml` files are now the starting point for GitOps authoring. Future work should enrich them in place instead of inventing a parallel desired-state format.
- `x-coolify` metadata preserves useful context such as `fqdn`, `uuid`, and `source_image`, but live-only destination wiring, domain attachment details, and runtime labels still need to be rehydrated from Coolify before any deploy.
- Some environment values are still intentionally redacted, and several apps still have no committed health check definition. Current readiness therefore cannot be proven from git alone.
- Legacy persistence hints were carried over only where earlier manifests exposed them, so stateful-storage assumptions still need live validation before cutover.

## 2. Recommended repository structure

Do not discard the current committed Portainer snapshots or the newly merged Coolify compose manifests. Keep them as the migration baseline, then layer operational metadata beside them.

Recommended end state inside the existing top-level folders:

```text
portainer/
  README.md
  GITOPS-MIGRATION-PLAN.md
  inventory/
    local/
      endpoint.json
      stacks/
        <stack>/...
  desired/
    stacks/
      dawarich/
        compose.yaml
        env.example
        secrets.sops.env
        cutover.md
      immich/
        compose.yaml
        env.example
        secrets.sops.env
        cutover.md
      monitoring/
        compose.yaml
        env.example
        secrets.sops.env
        cutover.md
      room-planner/
        compose.yaml
        env.example
        cutover.md

coolify/
  README.md
  applications/
    <app>/
      docker-compose.yaml
      env.example
      secrets.sops.env
      cutover.md
      smoke-check.sh
  inventory/
    exports-YYYYMMDD/
      applications.json
      applications/<app>/app.json
      applications/<app>/envs.redacted.json
```

Practical migration note:
- Keep the current committed paths (`portainer/local/...` and `coolify/applications/<app>/docker-compose.yaml`) stable; they are now the canonical baseline in git.
- For Coolify, enrich each existing app directory in place with env templates, smoke checks, and cutover notes instead of creating a parallel `desired/apps/*` tree.
- If a fresh raw Coolify export is needed later for diffing, store it under `coolify/inventory/` (or as task attachments), not in the primary deployment path.

## 3. Secret management approach

Goal: no plaintext runtime secrets in git, but the repo still defines all required secret names.

Recommended two-phase approach:

### Phase A: low-risk migration path
- Commit only `env.example` files, `docker-compose.yaml`, smoke checks, and cutover notes.
- Keep real secret values in the existing platform secret stores during the first cutover:
  - Portainer stack env editor / env files stored outside git
  - Coolify environment-variable store
- In git, add a small `secret-refs` section per workload documenting each key, owner, and where the real value currently lives.

### Phase B: full GitOps hardening
- Move actual secrets to `sops`-encrypted `.env` files in this repo (`secrets.sops.env`), encrypted with an `age` recipient controlled outside the host.
- Decrypt only in CI or in a local deployment runner immediately before applying.
- Never commit plaintext `.env` files, decrypted artifacts, or exported live secret values.

Why this split is recommended:
- It decouples “make deployment config declarative” from “replace the secret system”.
- It keeps the first migration small enough to do safely.
- It still leaves a clean path to fully reproducible GitOps later.

## 4. Global ordering constraints

1. Freeze the current Portainer snapshots and the current committed Coolify compose manifests; treat them as the baseline evidence and source material.
2. Build or enrich Git-managed desired state for every workload before touching any live deployment.
3. Add or document real health checks first, because current compose files and prior status snapshots are not enough for cutover verification on their own.
4. Migrate the easiest stateless Coolify apps first to prove the workflow.
5. Migrate `room-planner` next, because it is already Git-adjacent and low data risk.
6. Migrate stateful content/data workloads next (`danielkueffler`, `fathom`, `dawarich`, `immich`, `screeps`).
7. Migrate `monitoring` last so Grafana and VictoriaMetrics stay available while everything else changes.
8. Keep `deprecated/` untouched until all live Portainer/Coolify workloads are verified stable from the new source of truth.

## 5. Standard verification and rollback checkpoints

Use these checkpoints for every workload:

Before cutover:
- Desired-state files committed in `selfhosted`
- Secret keys mapped and validated out-of-band
- Backup or snapshot of persistent data taken and restore-tested for stateful workloads
- Staging deployment reachable on alternate port or alternate hostname
- Smoke check defined and runnable

During cutover:
- New deployment becomes healthy before traffic switch
- Traffic switch is one reversible step (proxy rule change, domain reassignment, or stop/start boundary)
- Old deployment remains intact until post-switch validation passes

After cutover:
- Public endpoint returns expected response
- Application logs show stable startup
- Background jobs / workers confirmed where applicable
- Observe for at least one soak window before deleting the old definition

Rollback rule:
- If the new deployment fails validation, revert traffic to the old target immediately.
- For stateful one-host cutovers that reuse the same data volumes, rollback is “redeploy previous compose/app definition against the same volumes”, not “run both at once”.

## 6. Portainer cutover plan

### 6.1 Portainer preparation phase
- Create `portainer/desired/stacks/<name>/` for all four stacks.
- Normalize compose filenames to `compose.yaml` in desired state, but do not change live stack entrypoints yet.
- Convert each `stack.env.example` into a canonical `env.example` plus a secret key inventory.
- Add per-stack smoke checks:
  - `dawarich`: HTTP 200 from app root after DB/Redis ready
  - `immich`: HTTP response from web UI / API and DB readiness
  - `monitoring`: Grafana login page and VictoriaMetrics `/health`
  - `room-planner`: existing port 5173 health check, plus app page load
- Decide whether to front these stacks with a reverse proxy first. Without that indirection, same-port blue/green is impossible.

### 6.2 `room-planner` (special case)
Target: move the deployment source of truth into `selfhosted` without losing the separate application-code repo.

Recommended path:
1. Keep `breuerfelix/screeps-room-planner` as the code repo.
2. Stop building directly from that repo in Portainer.
3. Add CI in `screeps-room-planner` that publishes an immutable image tag.
4. In `selfhosted`, define the Portainer stack using that image tag instead of a local build context.
5. Create a staged replacement stack on a temporary port.
6. Verify the staged instance against the same `SCREEPS_LOCAL_SERVER_URL` target.
7. Switch traffic by proxy or consumer endpoint update.
8. After soak, remove the old Git-backed Portainer linkage to the app repo.

Why this is best:
- `selfhosted` becomes the deployment source of truth.
- `screeps-room-planner` stays the application source repo.
- Image tags give deterministic rollback.

### 6.3 `dawarich`
1. Commit desired compose + env template.
2. Confirm exact live values for DB credentials, secret key, and bind-mount paths.
3. Take filesystem snapshots/backups of `/data/dawarich/*`.
4. If a reverse proxy is introduced first, stage on a temporary port; otherwise plan a maintenance window.
5. Stop the old stack.
6. Deploy the Git-managed stack reusing the same data paths.
7. Validate HTTP, DB connectivity, background worker startup, and import/watch directories.
8. Keep the old definition for rollback until soak completes.

Expected downtime: short maintenance window. With the current single-host direct-port layout, true zero downtime is not realistic.

### 6.4 `immich`
1. Commit desired compose + env template.
2. Confirm exact live values for `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, DB credentials, and `IMMICH_VERSION`.
3. Take database-consistent backup plus upload-library snapshot.
4. Pause writes/uploads if needed.
5. Redeploy from Git reusing the same storage.
6. Validate UI, API, background jobs, and machine-learning service readiness.
7. Resume writes after validation.

Expected downtime: short maintenance window. To get true zero downtime later, externalize DB/object storage and introduce proxy-based cutover first.

### 6.5 `monitoring`
1. Migrate this last.
2. Commit desired compose + env template.
3. Back up `/data/grafana` and `/data/victoriametrics`.
4. Redeploy using identical data paths and ports.
5. Validate Grafana login and VictoriaMetrics `/health` immediately.
6. Re-check dashboards that monitor the rest of the host.

Expected downtime: brief interruption is likely. Do not claim zero downtime for VictoriaMetrics on the current single-host single-data-dir layout.

## 7. Coolify cutover plan

Important design choice: treat `selfhosted` as the canonical desired-state repo and use the committed Compose files as the Coolify deployment baseline. Reconciliation can still happen through Coolify's API/UI, but the repo should now evolve the existing `docker-compose.yaml` files rather than recreate the old export format.

### 7.1 Coolify preparation phase
- Keep `coolify/applications/<name>/docker-compose.yaml` as the canonical per-app manifest.
- For each app, add beside it:
  - `env.example` with the canonical key list
  - `secrets.sops.env` later, once secret management is hardened
  - `cutover.md` with app-specific deploy/rollback notes
  - `smoke-check.sh` for post-deploy verification
- Rehydrate redacted env values from the live Coolify app before any deploy.
- Confirm destination/server/project/domain wiring against live Coolify, because the current repo snapshot does not fully encode it.
- Preserve the useful `x-coolify` metadata block, but do not rely on it alone for deployment-critical runtime behavior.
- Stop using mutable `latest` tags where possible; pin exact tags or digests before migration.

### 7.2 Stateless/low-risk Coolify apps first
Migrate in this order:
1. `redirect-breuer-dev`
2. `idle-proxy`
3. `travian-inactive-finder`
4. `noobgallery` (only after confirming no hidden local writable state)

For each of these apps:
1. Define desired state in git.
2. Create a duplicate Coolify app from the new desired state with a temporary hostname.
3. Inject secrets/env values from the existing secret store.
4. Verify via direct HTTP checks and logs.
5. Switch the production domain to the new app.
6. Keep the old app stopped but undeleted until the soak window passes.

Expected downtime: zero or near-zero if the domain/proxy switch is atomic.

### 7.3 `danielkueffler` (Ghost)
1. Confirm whether `database__connection__filename` means the live deployment uses a local SQLite file and where that file lives.
2. If it is local-file-backed, treat the app as stateful and plan a content freeze window.
3. Build desired state in git, ideally with an immutable image tag.
4. Stage a duplicate instance against copied data, not the live writable data.
5. During cutover, freeze writes/admin changes, take final backup, switch domain, and validate content/admin login.

Expected downtime: minimal-downtime at best on current data assumptions. True zero downtime requires externalized database/storage and replicated data path.

### 7.4 `fathom`
1. Resolve what database backend is actually in use; the committed compose file alone is not enough.
2. If it is local-file or single-instance DB backed, schedule minimal downtime.
3. Define desired state in git and stage a replacement.
4. Switch traffic only after explicit health and data checks pass.

Expected downtime: unknown until DB backend is confirmed; assume minimal downtime, not zero.

### 7.5 `screeps`
1. Do not migrate until the live storage and backup model are documented.
2. Determine whether the Coolify app stores world data locally, via mounted volume, or elsewhere.
3. Create a restore-tested backup before any cutover.
4. If a duplicate instance would fork world state, avoid parallel writes and use a brief maintenance window instead.

Expected downtime: unresolved/high risk until storage mapping is known. Do not promise zero downtime.

## 8. Monitoring checks to require during migration

For Portainer stacks:
- HTTP check on each published port after startup
- Container health status where health checks exist
- Disk free space before and after any data-copy step
- For `monitoring`, verify both Grafana and VictoriaMetrics separately

For Coolify apps:
- Public URL probe to expected endpoint
- Coolify logs during startup
- Treat `running:unknown` as provisional; do not use it as the only readiness signal
- Add real health checks in desired state wherever the app supports them

## 9. Gaps in the committed repo state that must be resolved before safe cutover

### Portainer gaps
- Real secret values are intentionally absent; only examples or key names are committed.
- For `immich`, exact live values of `UPLOAD_LOCATION`, `DB_DATA_LOCATION`, DB username/password, and `IMMICH_VERSION` must be pulled from the live stack.
- For `room-planner`, the live cutover path depends on how the current Git-backed Portainer stack is updated and whether a proxy exists in front of the UI.
- No front-proxy configuration is captured for the direct-port stacks, which limits blue/green options.

### Coolify gaps
- The repo now stores Compose manifests, but destination/server/project attachment still is not fully encoded in git.
- FQDNs are preserved in `x-coolify`, but the live domain-routing and proxy attachment details still need confirmation in Coolify before cutover.
- Some secret values remain redacted by design, and several apps still have no committed `env.example` companion file yet.
- Health checks are not encoded in the committed Compose manifests yet, so baseline readiness still is not fully observable from git alone.
- Persistent storage hints are only partial: `ghost-data`, `fathom-data`, and `screeps-data` were carried over where legacy manifests exposed them, but live mount semantics still need validation.
- Several apps still reference mutable `latest` tags, which weakens deterministic rollback until pinned.
- `danielkueffler`, `fathom`, and especially `screeps` need live storage/backup details before any honest downtime plan can be finalized.

## 10. Recommended migration sequence

1. Commit desired-state skeletons for all workloads.
2. Add health checks and smoke checks.
3. Migrate `redirect-breuer-dev` as the first proof of process.
4. Migrate `idle-proxy` and `travian-inactive-finder`.
5. Migrate `noobgallery` after storage verification.
6. Convert `room-planner` to image-based deployment controlled from `selfhosted`.
7. Migrate `danielkueffler` and `fathom` after resolving storage details.
8. Migrate `dawarich`.
9. Migrate `immich`.
10. Migrate `screeps` only after state/backups are fully documented.
11. Migrate `monitoring` last.
12. Only then decide whether anything in `deprecated/` can be archived further or deleted.

## 11. Bottom line

- Zero downtime is realistic for the stateless Coolify apps and likely for `room-planner` after it is converted to image-based deployment with staged cutover.
- Zero downtime is not an honest promise for `dawarich`, `immich`, `monitoring`, `danielkueffler`, `fathom` (until DB/storage is clarified), or `screeps` with the current committed evidence.
- The safest path is: preserve the Portainer snapshots, treat the merged Coolify Compose files as the GitOps baseline, enrich them with missing operational metadata, prove the workflow on stateless apps first, and only then cut over the stateful workloads with explicit rollback points and backups.
