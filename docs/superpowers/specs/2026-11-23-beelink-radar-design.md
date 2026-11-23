# Beelink Radar trial

## Intent

Try Radar on Beelink before deciding whether to keep it or deploy it elsewhere.

## Design

- Deploy one pinned upstream Radar Helm chart through the existing Beelink Flux apps reconciliation, in namespace `radar`.
- Expose HTTPS at `radar.vulture-skink.ts.net` through the existing Tailscale ingress operator. Do not create public, LAN, NodePort, hostPort, or Funnel access.
- Use the chart's default read-only Kubernetes permissions, read-only MCP, no pod exec, and no general Secret access or Helm writes. Logs and ConfigMaps remain readable; Tailscale access controls are the access gate, without a separate application login.
- Keep the default in-memory timeline and no persistent volume. History is lost on restart. Do not configure Cloud, usage reporting, a database, or backups.
- Follow existing namespace, Kustomization, HelmRelease, and ingress patterns. Keep scheduling unconstrained for this permanently single-node cluster.
- Document the access URL and limitations. Ensure Renovate discovers the application HelmRelease.

## Approaches

Use the upstream chart with Flux: it supplies Radar's RBAC and hardened workload defaults without duplicating upstream manifests. A direct Helm install would bypass the repository's source of truth. Persistent storage and extra login infrastructure are unnecessary for this read-only, tailnet-only trial.

## Verification and rollout

Render Kustomize and the pinned chart, inspect permissions and network exposure, and validate against Beelink's API. Obtain an independent review, then commit and push only this change to `main` for Flux to deploy; do not install Radar directly. Check Flux adoption, readiness, effective read-only permissions, Tailscale HTTPS, and lack of public/LAN endpoints. Notify the user when Radar is ready to try.
