# Papra on Beelink

Migrated on 1 November 2026 from Portainer stack 37 into namespace `papra`.
Open <https://papra.vulture-skink.ts.net/> with Tailscale connected and sign in
with the existing account. Browser validation is a user step; no browser was
operated during migration.

## Runtime and ownership

Flux manages `cluster/apps/papra` through `cluster/papra-sync.yaml`. One
Recreate Deployment runs on node `beelink` as UID:GID `1000:1000`, retaining
`ghcr.io/papra-hq/papra:26.7.0-rootless` at its original digest:

```text
sha256:bf4a66e776d0a40d71543747a2e17af800204b4a81d19f7951b8552c8032dbeb
```

There was no application upgrade. Static PV/PVC `papra-data` use empty storage
class, explicit binding in both directions, local path `/data/papra`, node
affinity `beelink`, and `Retain`. Namespace, PV, and PVC have Flux prune
protection. The 10 GiB capacity is a binding declaration, not a filesystem
quota. The existing SSD mount/startup guard remains required.

The original directory is mounted directly at `/app/app-data`; no ownership
change, copying into replacement storage, or database conversion occurred.
Effective paths were verified before and after cutover:

| Setting | Effective value |
|---|---|
| SQLite database | `/app/app-data/db/db.sqlite` → `/data/papra/db/db.sqlite` |
| Document filesystem root | `/app/app-data/documents` → `/data/papra/documents` |
| Configuration search directory | `/app/app-data` → `/data/papra` |
| Application/client/server/auth base URL | `https://papra.vulture-skink.ts.net` |

No Papra config file or additional runtime URL/auth override existed. Source
inside the pinned image confirms `APP_BASE_URL` overrides client/server URLs,
sets Better Auth's base URL, and supplies its trusted client origin. HTTPS
automatically selects secure session cookies; no separate auth URL or trusted
origin override is required. See [Papra configuration](https://docs.papra.app/self-hosting/configuration/).
`AUTH_SECRET` was transferred without printing it, encrypted with the existing
Hetzner/Beelink SOPS age recipient, round-trip checked, and compared byte for
byte against the running Kubernetes Secret.

Only a ClusterIP Service targets TCP 1221. Tailscale operator Ingress provides
HTTPS; no LAN Service, NodePort, hostPort, hostNetwork, or Funnel is configured.
Tailnet-wide device inventory confirmed hostname availability before cutover;
the resulting device and certificate use exactly `papra.vulture-skink.ts.net`.
See [Tailscale Ingress](https://tailscale.com/docs/kubernetes-operator/ingress).

Original Docker container `papra` (`1db935b9c60c…`) remains stopped with
`restart=no`. Portainer's active stack records confirmed automatic updates
are disabled for both Papra stack 37 and backup stack 35, without redeploying
Papra. The user also disabled automatic updates for all other Portainer stacks;
this migration did not change those stacks. Keep them disabled; the old Compose file is rollback-only. Never start
Docker Papra while a Kubernetes Papra pod exists.

## Verification

- The staged sync was first pushed with `suspend: true`; no Kubernetes writer
  started until Docker was stopped and stopped-writer recovery was verified.
- Kustomize rendering, strict schema validation, and server-side dry-runs
  passed. Namespaced child dry-runs used the existing `default` namespace,
  since the suspended app namespace did not yet exist; nothing was applied.
- Flux Papra is Ready; retained PV/PVC are Bound. Runtime mount information
  confirms ext4 `/dev/nvme0n1` subdirectory `/papra` at `/app/app-data`, with
  actual process UID/GID `1000:1000` and preserved file ownership.
- SQLite `integrity_check` returned `ok`. Every database table matched its
  pre-cutover row hash immediately after startup. One user, one organization,
  five documents, original password records, and existing configuration remain.
- HTTPS `/api/health` returns HTTP 200 with `isDatabaseHealthy=true` and
  `isEverythingOk=true`; the UI returns 200 with certificate verification.
  The certificate covers the exact final hostname and expires 30 January 2027.
- A temporary five-minute signed session for the existing user verified
  session authentication and downloaded all five originals over HTTPS. Each
  response size and SHA-256 matched the database. The temporary session was
  deleted afterward; existing user/password/session records were rechecked
  unchanged in the new Restic restore. This tests session authentication,
  not the user's password login. Incorrect passwords return 401; tampered
  session cookies fail; unauthenticated document downloads return 401.
- Host TCP 1221 has no listener and is unreachable from the Mac. Papra has
  only its ClusterIP Service and Tailscale ingress.
- The existing backup now quiesces Kubernetes Papra. Forced Flux reconciliation
  during the pause left zero Papra pods and replicas at zero. A deliberate
  failure exited nonzero and restored Papra/readiness through the cleanup trap.
  Missing kubeconfig fails before stopping any Docker containers or snapshotting.
- Backup RBAC allows get/patch only Deployment `papra/papra` and listing Papra
  pods; reading Secrets and modifying monitoring workloads were denied.

User browser steps: sign in with the existing password at the final URL,
open/download an existing document, and check the account/organization UI.
No password reset or new account is needed. The new hostname requires a fresh
browser login because cookies from the former LAN address do not transfer.

## Backups

Root-only recovery artifacts on `ssh bee`:

```text
/var/backups/papra-migration-20261101/
  docker-original.json
  all-docker-before.json
  restic-docker-original.json
  baseline.json
  data.tar
  data.tar.sha256
  backup-verified.json
  restic-verified.json
  restic-restore-test/
  stopped-writer-restore/
  post-cutover-restic-restore/
  final-restic-restore/
```

The directory is 0700 and credential-bearing metadata/archive files are 0600.
`data.tar` was created with all writers stopped, preserving numeric ownership,
ACLs, and xattrs. Full archive/source comparison, extraction, SQLite integrity,
and all document hashes passed. SHA-256:

```text
2a55d248ec488fcb32460227783a660f4763287dffe79b0c596006418ec3e89e
```

Pre-cutover offsite Restic snapshot `a9b4a9cb` was restored and verified before
stopping Docker. New snapshots `cd49c8da` and `2d7dfc00` were created by the updated backup job
with Kubernetes Papra quiesced, then both restored independently: SQLite integrity,
all five document hashes, users/password/session records, memberships, and
migration records passed. `2d7dfc00` verifies the final deployed backup image.

Restic remains in Docker, version 0.19.1. Only its image/container changed to
`selfhosted-restic-backup:0.19.1-papra-k3s1`. Existing repository credentials,
hostname, mounts, network, retention, schedules, and four-path include list
are preserved. Hindsight and Portainer still follow their existing stop/start
backup lifecycle; monitoring and all other applications remain outside it.
The original backup container is retained stopped with restart disabled as
`restic-backup-pre-papra-k3s`.

The 03:00 Europe/Berlin backup first uses a scoped kubeconfig to mark the Papra
Deployment with `kustomize.toolkit.fluxcd.io/reconcile: disabled`, scale to zero,
and wait until its pods disappear. Flux honors this live resource annotation
and skips that Deployment even during forced reconciliation. An EXIT/signal
trap restores replica count/readiness and removes the override. Other Flux
applications are not suspended. See [Flux resource reconciliation](https://fluxcd.io/flux/components/kustomize/kustomizations/)
and the [backup maintenance and interrupted-job recovery procedure](../../portainer/restic-backup/README.md).
The scoped credential is `/data/restic-backup/papra.kubeconfig` (directory 0700,
file 0600), outside Restic's explicit include list. Recreate it after cluster
rebuild or token rotation:

```bash
ssh bee python3 - < beelink/scripts/configure-papra-backup.py
```

For an archive restore, first stop both runtimes. In the protected backup
directory, run `sha256sum -c data.tar.sha256`, then extract using GNU tar
`--acls --xattrs --numeric-owner -xpf data.tar -C <clean-restore-directory>`.
Validate there before replacing data. Preserve the current tree separately;
never extract over a running or populated dataset. Normal rollback reuses
current data and needs no restore. Local artifacts alone do not protect
against host loss; verified Restic snapshots provide offsite recovery.

## Rollback

1. Commit `suspend: true` in `beelink/cluster/papra-sync.yaml`, push, reconcile
   root Flux, and verify the live Papra Kustomization is suspended. If Git is
   unavailable, suspend root Flux first, then Papra; commit the suspended state
   before resuming root reconciliation.
2. Ensure no backup is running. Scale only Deployment `papra/papra` to zero
   and wait until every Papra pod/process has exited. Retain namespace, PV,
   PVC, and all data. Delete only Ingress `papra/papra` while Flux is suspended
   and confirm its Tailscale proxy is removed.
3. Return backups to Docker mode before starting Docker Papra. Either set
   `PAPRA_RUNTIME=docker` in Portainer backup stack 35 and redeploy only that
   stack, or restore the original retained scheduler using these commands:

   ```bash
   ssh bee
   docker stop restic-backup
   docker update --restart=no restic-backup
   docker rename restic-backup restic-backup-k3s
   docker rename restic-backup-pre-papra-k3s restic-backup
   docker update --restart=unless-stopped restic-backup
   docker start restic-backup
   ```

   Record Docker backup mode in Git before any later stack 35 redeployment.
   Do not run both backup schedulers.
4. After verifying zero Kubernetes writers, start the retained Docker Papra:

   ```bash
   ssh bee 'docker update --restart=unless-stopped papra && docker start papra'
   ```

   Original image, secret, data path, and `APP_BASE_URL` remain on that container;
   its original access URL is `http://192.168.178.13:1221`. Keep Portainer
   automatic updates disabled. Verify login, document access, and backups.
5. Keep Flux Papra suspended while Docker owns `/data/papra`. Do not manually
   apply child manifests. Only restore the pre-cutover archive if data recovery
   is necessary, with both runtimes stopped and current data preserved separately.
