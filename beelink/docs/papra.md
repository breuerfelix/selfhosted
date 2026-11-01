# Papra on Beelink

Open <https://papra.vulture-skink.ts.net/> with Tailscale connected and use
your existing account. Papra runs in namespace `papra`, managed by Flux from
`cluster/apps/papra` through `cluster/papra-sync.yaml`.

## Deployment

- One replica, Recreate strategy, pinned to node `beelink`.
- Image `ghcr.io/papra-hq/papra:26.7.0-rootless`, pinned to digest
  `sha256:bf4a66e776d0a40d71543747a2e17af800204b4a81d19f7951b8552c8032dbeb`.
- UID:GID `1000:1000`, matching the original Docker process and data ownership.
- Original `/data/papra` mounted directly at `/app/app-data` through explicitly
  bound local PV/PVC `papra-data`, empty storage class, and `Retain` policy.
  Namespace, PV, and PVC are protected from Flux pruning.
- ClusterIP Service targeting TCP 1221, exposed through Tailscale HTTPS only.
  No LAN Service, NodePort, hostPort, or hostNetwork.
- Original `AUTH_SECRET` encrypted with the existing Hetzner/Beelink SOPS age key.

| Setting | Value |
|---|---|
| Database | `/app/app-data/db/db.sqlite` |
| Documents | `/app/app-data/documents` |
| Configuration directory | `/app/app-data` |
| `APP_BASE_URL` | `https://papra.vulture-skink.ts.net` |

`APP_BASE_URL` also supplies the client/server URLs and authentication origin.
No separate URL/auth override is needed.

Papra backups are disabled. No backup ServiceAccount, RBAC, Kubernetes token,
or quiescing hooks are installed. The Docker Restic job excludes `/data/papra`.
Existing recovery archives and snapshots from migration remain available.

## Validation

Migration on 1 November 2026 preserved the database, one user, one organization,
five documents, ownership, configuration, and auth secret without upgrading
Papra. SQLite integrity, HTTPS certificate, backend health, signed-session
access, and downloads of all five documents passed. Download hashes matched
the database. User password login remains a browser verification step.

## Rollback

1. Set `suspend: true` in `cluster/papra-sync.yaml`, commit/push, reconcile root
   Flux, and verify the live Papra Kustomization is suspended.
2. Scale Deployment `papra/papra` to zero and wait until every Papra pod has
   exited. Retain namespace, PV, PVC, and all data.
3. Delete Ingress `papra/papra` while reconciliation is suspended and wait for
   its Tailscale proxy to disappear.
4. Start the retained Docker container only after all Kubernetes writers stop:

   ```bash
   ssh bee 'docker update --restart=unless-stopped papra && docker start papra'
   ```

   Its original URL is `http://192.168.178.13:1221`. Keep Portainer stack 37
   automatic updates disabled and Flux Papra suspended while Docker owns the data.
