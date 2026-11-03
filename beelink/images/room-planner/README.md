# Room Planner image

The source repository `breuerfelix/screeps-room-planner` is private; its GHCR
package is public and supports anonymous pulls. No registry Secret is required.

The upstream `room-planner-image.yml` workflow publishes `latest` on pushes to
`main`. The Deployment in `cluster/apps/room-planner/app.yaml` uses
`latest@sha256:…`; Renovate proposes digest updates through the normal Kubernetes
manager. Merge those updates to deploy through the shared `apps` Flux sync.

The image builds the frontend with `VITE_ROOM_PLANNER_API_BASE_URL=/plan`.
Runtime `ROOM_PLANNER_PROXY_URL` points the UI server at its local proxy on port
3001. `__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS` allows the exact Tailscale hostname
through Vite's host check. Only the UI port 5173 is exposed through the ClusterIP
Service and Tailscale HTTPS ingress. No LAN service, public ingress, or Funnel is
configured.

`source.json` records the historical migration build on `codex/k3s-room-planner`.
It is retained for provenance and does not select the running image. That branch
starts at the old application version; do not merge it over upstream `main`.
