# Coolify compose GitOps export

Docker Compose-compatible manifests for the current Coolify-managed applications.

Layout:
- Each application has a manifest at `coolify/<app>.yaml`.
- Environment variable keys are preserved, but values remain `[REDACTED]` where the source Coolify export redacted them.
- Legacy persistence hints were carried over where the earlier Kubernetes manifests made them explicit.
- Coolify-generated runtime labels were not available in the committed export and therefore are not reproduced here.
- These files are repository-only GitOps artifacts. No live deployment change is performed by this repo update.
- The migration/cutover plan for moving these manifests into real GitOps operation lives in `portainer/GITOPS-MIGRATION-PLAN.md`.

Applications:
- danielkueffler
- fathom
- idle-proxy
- noobgallery
- redirect-breuer-dev
- screeps
- travian-inactive-finder
