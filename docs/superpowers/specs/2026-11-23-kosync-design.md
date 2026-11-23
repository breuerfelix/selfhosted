# KOReader sync on Hetzner

Approved in chat: deploy the official server at `https://kosync.felixbreuer.me`, with the smallest setup that follows this repository's patterns.

## Approach

Use the official `koreader/kosync` image, pinned by digest. Its bundled Redis avoids another Deployment or database service. SQLite and .NET alternatives add third-party implementation choices without reducing the Kubernetes resources needed here.

## Design

- One `apps/kosync` Deployment with one replica and `Recreate`, plus a ClusterIP Service targeting HTTP port `17200`.
- One retained, explicitly bound `kosync-data` hostPath PV/PVC, using `/data/kosync` with `type: Directory`, mounted at `/var/lib/redis`.
- Traefik and the existing Let's Encrypt issuer provide HTTPS for `kosync.felixbreuer.me`. Redis is not exposed.
- Registration starts enabled. The user registers through KOReader, then registration is disabled in Git with `ENABLE_USER_REGISTRATION=false`.
- Ansible prepares the host directory. Add the Deployment to the existing nightly backup list; no ad hoc backups or new backup system.
- Plain manifests, no Helm chart, custom image, new secrets, scheduling constraints, or separate Redis.

## Verification and limits

Validate rendered manifests and Ansible syntax, reconcile Flux through the normal Git deployment workflow, and check rollout, PVC, certificate, public health, authenticated progress round trips, and persistence across a restart. Use a temporary test account and remove only its own Redis keys afterward. Actual reader setup remains the user's step. This syncs reading progress, not books or annotations.
