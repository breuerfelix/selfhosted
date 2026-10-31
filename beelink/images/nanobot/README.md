# Nanobot image build

`source.json` pins the upstream repository, complete commit SHA, version, image repository, and optional build extras/channels. GitHub Actions builds the upstream Dockerfile directly; this repository does not maintain a forked Dockerfile or copy application sources.

The entrypoint is `.github/workflows/build-nanobot.yml`. A push to `main` changing that workflow or this image directory starts a build; it can also be run manually from GitHub Actions. Only `linux/amd64` is needed for Beelink. Empty channel/extras arguments omit optional integrations; the built-in WebSocket channel remains available.

Before publication, `smoke-test.sh` starts the image as UID:GID `1000:1000` with a disposable tmpfs and no network. It verifies the gateway health endpoint, WebUI HTML, and built frontend assets. CI never mounts `/data/nanobot` or receives application/SOPS/Tailscale credentials.

Each successful run publishes a unique tag and records its registry digest. A second job opens/updates `codex/nanobot-image`, changing only the Deployment image and pull policy. It does not change the nanobot suspension setting. Merge that PR to deploy the digest through Flux. Keep nanobot suspended until the first Docker-to-Kubernetes cutover is ready.

GitHub Actions uses its built-in `GITHUB_TOKEN`; no personal publishing token is required in repository secrets. Repository Actions settings must allow Actions to create pull requests. Set the new GHCR package to public for anonymous cluster pulls; a new package starts private. These are one-time GitHub settings.

For upgrades, change both version and commit in `source.json`, review the pinned upstream changes, and merge. CI builds/tests/publishes and proposes the resulting digest. A source pin does not freeze upstream base-image tags or Python dependency resolution; the Deployment digest freezes the actual artifact. Existing builds remain available for rollback.

Local smoke check on an amd64 Docker host:

```bash
bash beelink/images/nanobot/smoke-test.sh <built-image>
```

Do not mount the production SSD for this smoke check. Live migration and rollback remain in `beelink/docs/bootstrap.md`.
