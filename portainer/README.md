# Portainer export

Snapshot of the current Portainer-managed deployments on endpoint `local` (Portainer endpoint id `3`).

Stacks exported:
- `immich`
- `dawarich`
- `monitoring`
- `room-planner`

Notes:
- This repository import does not change the live Portainer deployments.
- Secret values are intentionally redacted or moved to example env files before they are committed to git.
- `metadata.json` keeps the Portainer stack id, endpoint id, status, timestamps, and Git metadata when present.
- `room-planner` is already Git-backed in Portainer; its deployed stack entrypoint is mirrored here for GitOps inventory purposes.
- The current migration/cutover plan for both Portainer and Coolify lives in `portainer/GITOPS-MIGRATION-PLAN.md`.
