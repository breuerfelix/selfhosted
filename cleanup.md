# Coolify cleanup

Verified 2026-11-04, Europe/Berlin, against Git revision `c27996f`, the live VPS over SSH, the Hetzner Kubernetes API, public DNS/HTTPS, and accessible GitHub repository settings. The original investigation made no server, DNS, or account changes. The subsequent application storage migration is recorded below.

## Conclusion

All applications retained in the migration are running through K3s. No further application migration is required to remove Coolify. Remaining work is runtime, data, access, DNS, and repository cleanup.

Application storage migration on 2026-11-04 moved Ghost, Fathom, and Screeps to `/data/ghost`, `/data/fathom`, and `/data/screeps`. Ownership and permissions are preserved. Coolify runtime teardown and legacy-data retention decisions remain separate work. The original investigation below is updated for these active paths; disk-usage figures describe the pre-migration snapshot.

## Application storage migration, 2026-11-04

| App | Previous path | Current path | Entries verified |
| --- | --- | --- | ---: |
| Ghost | `/srv/k3s-data/ghost` | `/data/ghost` | 1,871 |
| Fathom | `/srv/k3s-data/fathom` | `/data/fathom` | 2 |
| Screeps | `/data/coolify/applications/screeps` | `/data/screeps` | 19,069 |

Root and app Flux syncs were paused manually, and all three stateful Deployments were stopped before same-filesystem directory renames. File identities, ownership, permissions, sizes, modification times, and database SHA-256 hashes matched before and after each move. The empty `/srv/k3s-data` parent was removed. Static PV/PVC names and `Retain` policy remain unchanged; PV objects are recreated for the new immutable host paths. Manifests, Ansible setup, and operations docs use the new locations. Deployment replica counts remain one in Git so Flux restores them when reconciliation resumes. No backups were created and no legacy Coolify data was deleted.

## Migration completeness

| Application | Live state | Remaining migration |
| --- | --- | --- |
| Ghost | Deployment ready; retained PV at `/data/ghost`; valid HTTPS at `danielkueffler.de` | None |
| Fathom | Deployment ready; retained PV at `/data/fathom`; valid HTTPS at `stats.felixbreuer.me` | None |
| Noobgallery | Deployment ready; valid HTTPS at `photos.felixbreuer.me` | None |
| Screeps | Deployment ready; retained PV at `/data/screeps`; `/api/version` returns `ok: 1` and two users over valid HTTPS | None; keep active data directory |
| Domain redirect | Native Traefik routes redirect HTTP and HTTPS for `felixbreuer.me` to `https://breuer.dev/` | None |
| Travian inactive finder | Old Docker container stopped; no Kubernetes route | Intentionally retired at user request in commit `d167316` |
| Idle MMO proxy | Old Docker container stopped; no Kubernetes route | Intentionally retired at user request in commit `d167316` |

All six Flux Kustomizations were Ready at `main@sha1:c27996fe`. All three application PVs/PVCs were Bound with `Retain`. All five application certificates were Ready. The Ghost and Fathom target directories are real directories, not symlinks into Coolify. These checks establish deployment and routing health; they are not a fresh-host restore test.

## 1. Remove retired Docker resources

Docker has zero running containers and 13 stopped containers. Every container has restart policy `no`.

| Group | Containers |
| --- | --- |
| Coolify control plane | `coolify`, `coolify-realtime`, `coolify-db`, `coolify-redis` |
| Coolify host services | `coolify-proxy`, `coolify-sentinel` |
| Replaced application containers | `screeps`, `danielkueffler`, `fathom`, `hk800wo04cg40kskco04g8k4-182621145125` (redirect), `tcwk0w00ssookk84w8880oog-150844045641` (Noobgallery) |
| Retired application containers | `qw08wsg44cgossk8sg0sws8k-112020026593` (Travian), `wwgk8sgck44gocwscc0gs4ck-111920518419` (Idle MMO) |

Remove these exact stopped containers, then the `coolify-db` and `coolify-redis` named volumes, the `coolify` Docker network, and retired Docker images. There are no other Docker volumes. No application depends on the Docker proxy: public routes already work while it is stopped.

Removing the old `screeps` container is desirable because it is retired and still references the old storage location. Do not restart it. Container removal must preserve all retained host files.

Use the [upstream uninstall procedure](https://coolify.io/docs/core/instance-management/uninstallation) for resource categories, adapted to this inventory. Review remaining legacy worlds before deleting `/data/coolify`. Active application data now lives outside it. Use named resources rather than broad volume pruning.

## 2. Remove obsolete files selectively

Approximate disk usage measured with `du`; live Screeps sizes change while it runs.

| Path | Size | Disposition |
| --- | ---: | --- |
| `/data/screeps` | 957 MiB | **Keep. Active world/player data, dependencies, and logs. Preserve ownership.** |
| `/data/coolify/sentinel` | 3.2 GiB | Obsolete monitoring history; remove with Sentinel retirement |
| `/data/coolify/applications/daniel` | 2.7 GiB | Old Ghost tree; replacement uses `/data/ghost` |
| `/data/coolify/applications/fathom` | 2.8 MiB | Old Fathom tree; replacement uses `/data/fathom` |
| `/data/coolify/applications/screeps2` | 709 MiB | Unreferenced legacy world; contains a nonempty database. Decide data retention before removal |
| `/data/coolify/applications/screeps3` | 726 MiB | Unreferenced legacy world; contains a nonempty database. Decide data retention before removal |
| `/data/coolify/source` | 2.6 MiB | Compose files, upgrade scripts/logs, `.env`, and many historical `.env-*` copies; remove after credential review |
| `/data/coolify/ssh` | 16 KiB | Coolify private SSH key and lock files; remove after revoking its authorized public key |
| `/data/coolify/proxy` | 136 KiB | Old routing and ACME state; remove after proxy container retirement |
| Other Coolify application UUID directories | Small | Old deployment/config files; remove after configuration and credential review |
| Remaining Coolify service directories | Small | No running consumers found; remove after review |
| `/var/lib/docker` | 4.7 GiB | Docker state; remove after resource and Docker retirement |
| `/var/lib/containerd` | 768 KiB | Separate Docker-side containerd state; remove after package/runtime retirement |

Before migration, `/data/coolify` totaled about 8.2 GiB, including about 957 MiB of live Screeps data now moved to `/data/screeps`. Around 12 GiB is potentially reclaimable across obsolete Coolify data and Docker state, depending on legacy-world retention. Do not sum Docker's logical image sizes on top of `/var/lib/docker` usage.

The current local-path storage directory `/var/lib/rancher/k3s/storage` is empty; there is no remaining dynamic Screeps directory there to migrate or remove.

Additional legacy artifacts exist under `/root/default-storage` (old Ghost, Fathom, Screeps, and Paperless PVC directories) and `/root/storage.zip`. No current Hetzner PV references them. Their contents, provenance, and retention requirements were not established; treat them as a separate legacy-data review, not automatic Coolify deletion targets.

The accepted backup policy remains the planned nightly AWS S3 job tracked in `TODO.md`. No ad hoc volume backup is required for this cleanup. The job remains unimplemented; that is separate work, not a newly introduced teardown prerequisite.

## 3. Revoke Coolify access and review external integrations

The Coolify private key under `/data/coolify/ssh/keys/ssh_key@g4484kk844sc4g8cgs88kkk0` matches the ED25519 entry commented `coolify` in `/root/.ssh/authorized_keys`:

```text
SHA256:KEwk+UcwIdbkLqKGiwOzsJ4U3EUJ4J7ldlGTffA7jGg
```

Remove that exact authorized key, preserving the other administration key. Verify a fresh administrative SSH connection before deleting Coolify's private key files.

Review external credentials that were granted specifically to Coolify: GitHub Apps/deploy keys/webhooks, registry credentials, provider/DNS API tokens, notification integrations, and any tokens used to call Coolify's API. Revoke dedicated credentials; shared credentials require checking active consumers first. Deleting a local token copy does not revoke its provider-side grant.

Verified GitHub repository webhook state:

- `breuerfelix/selfhosted`: no repository webhooks.
- `breuerfelix/idle-mmo-extensions`: no repository webhooks; no Actions secrets or variables.
- `breuerfelix/travian-inactive-finder`: two active hooks targeting `cloud.docker.com` and `kolkrabbi.heroku.com`; no Actions secrets or variables. These are not Coolify hooks. Review them separately if retiring the application's remaining external services.

This was not an account-wide GitHub installation/deploy-key audit. Coolify's database remains stopped and was not queried for encrypted provider credentials, scheduled-task definitions, other connected servers, or notification configuration. Those external dependencies remain an explicit verification gap; do not assume they exist or have been revoked.

No Coolify references were found in the inspected host systemd units, cron directories/spools, or logrotate configuration. There are no user crontabs. Coolify has no running process to perform its former scheduled tasks or self-updates.

## 4. Remove Docker from the host

Docker, `docker.socket`, and the separate `containerd.service` remain enabled. Docker and that containerd are active despite having no running containers. Their only reported Docker service reverse dependency is the normal boot target.

K3s uses its own bundled runtime. The two live containerd processes resolve to:

- Docker-side process: `/usr/bin/containerd`.
- K3s-side process: executable under `/var/lib/rancher/k3s/data/<hash>/bin/k3s`, running as `containerd`.

This matches [K3s's default bundled containerd architecture](https://docs.k3s.io/advanced#using-docker-as-the-container-runtime). Removing Docker does not require a Kubernetes runtime migration.

After deleting retired Docker resources, disable/remove Docker services and packages: `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras`, `docker-buildx-plugin`, `docker-compose-plugin`, and Docker's `containerd.io`. Review the package transaction before applying it. Remove obsolete `/etc/docker/daemon.json`, Docker-side `/etc/containerd/config.toml`, `/etc/apt/sources.list.d/docker.list`, `/etc/apt/keyrings/docker.asc`, and Docker-only user state if no longer wanted.

Preserve `/var/lib/rancher/k3s`, `/etc/rancher/k3s`, `/var/lib/kubelet`, Kubernetes networking, and the active `/data/ghost`, `/data/fathom`, and `/data/screeps` directories. Do not flush host iptables/nftables rules as Docker cleanup; active K3s networking uses them.

## 5. Clean DNS and verify provider firewall

The former dashboard hostname `coolify.felixbreuer.me` is confirmed in the old proxy configuration. It, `inactive-finder.felixbreuer.me`, and `idle-proxy.felixbreuer.me` still resolve to `91.99.161.123`; all fail HTTPS certificate validation against the current ingress.

A fresh arbitrary name, `retirement-check-20261104.felixbreuer.me`, resolves to the same address. This indicates wildcard DNS. Provider-side inspection is needed to distinguish explicit records from wildcard answers. Deleting individual records alone may leave retired names resolving. Review whether the wildcard should remain or be replaced by explicit records for retained applications. Keep working application A records; no AAAA answers were returned for the tested VPS application names.

UFW is inactive and host INPUT policies are ACCEPT with K3s-managed chains. No legacy Coolify dashboard/realtime listener was present. The Hetzner Cloud Firewall was not accessible in this investigation. Review its live rules and remove obsolete allowances for dashboard/realtime or former direct application ports, if present. Preserve public TCP 80/443, administration SSH access, and restricted Kubernetes API access as described in [Hetzner rebuild](hetzner/docs/rebuild.md). Do not delete the VPS: K3s uses the same machine.

## 6. Clean repository references without changing identities

| Reference | Action |
| --- | --- |
| `renovate.json` ignores `coolify/**` and `deprecated/**` | Remove both obsolete ignore entries; both directories were deleted in commit `b809ae7` |
| Application PVs, Ansible storage setup, and operations docs | Updated to `/data/ghost`, `/data/fathom`, and `/data/screeps`; preserve these active paths |
| Screeps `shardName: coolify` | Keep unless a coordinated game/client/metrics rename is wanted |
| Beelink private agent `SCREEPS_SHARDS: coolify` | Consumes the current shard name; changing only the server config would leave a mismatched consumer |
| Hostname/Kubernetes node `coolify` and SSH alias `cool` | Cosmetic; leave in this cleanup. A host/node rename is separate work with K3s identity and local access implications |
| Old Coolify Compose exports | Already removed; no need to restore or migrate them |
| Operations docs repeatedly require current off-server backups | Align wording with the accepted nightly-S3 policy and `TODO.md`; do not introduce ad hoc backup gates |
| Ignored `temp/coolify-migration` artifacts | Local archive and SQLite copies remain; review retention separately. Preserve kubeconfigs and the SOPS identity |

The public Screeps API currently advertises the `coolify` shard. That string does not imply a dependency on Coolify software. Removing every occurrence of the name is a different goal from removing its runtime and access.

## Suggested execution order

1. Recheck current Flux/app health, PV paths, container inventory, and a fresh administrative SSH connection.
2. Review dedicated external credentials and remaining legacy-world retention decisions while Coolify metadata is still available. Do not restart the old application stack.
3. Remove the 13 named stopped containers, two named volumes, the Docker network, and retired images. Keep all live application data untouched.
4. Revoke the exact Coolify root SSH key and dedicated external grants. Delete obsolete Coolify files selectively, preserving `/data/ghost`, `/data/fathom`, and `/data/screeps`. Leave unclassified legacy worlds/artifacts until their retention is settled.
5. Disable/remove Docker and its separate containerd, then their obsolete files and package source. Recheck K3s and public routes.
6. Clean DNS/provider firewall settings and repository-only stale references. Verify retained routes, certificates, PVCs, Flux, and Screeps world/agent behavior again.

Completion means no Coolify containers, services, private keys, dedicated authorized access, or required external integrations remain; retired Docker state is gone if Docker is removed; retained applications remain healthy. The Screeps shard identity still uses the word `coolify` without requiring Coolify itself.
