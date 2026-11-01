# Nanobot image build

`source.json` pins the upstream repository, complete commit SHA, version, image repository, and optional build extras/channels. GitHub Actions builds the upstream Dockerfile unchanged, then uses that image as the base for this directory's `Dockerfile`. The local Dockerfile adds GitHub CLI (`gh`) and runs as the upstream `nanobot` user. This repository does not fork the upstream Dockerfile or copy application sources.

The entrypoint is `.github/workflows/build-nanobot.yml`. A push to `main` changing that workflow or this image directory starts a build; it can also be run manually from GitHub Actions. Only `linux/amd64` is needed for Beelink. Empty channel/extras arguments omit optional integrations; the built-in WebSocket channel remains available.

The upstream build uses the cached Buildx container builder and loads an intermediate image tagged with `-upstream` into Docker. The local build uses the `default` Docker builder so it can read that image from Docker's image store. Only the final customized image is tested and published to GHCR.

Before publication, `smoke-test.sh` starts the final image as UID:GID `1000:1000` with a disposable tmpfs and no network. It verifies GitHub CLI runs without root, the gateway health endpoint, WebUI HTML, and built frontend assets. CI never mounts `/data/nanobot` or receives application/SOPS/Tailscale credentials.

Each successful run publishes a unique tag and records its registry digest. A second job opens/updates `codex/nanobot-image`, changing only the Deployment image. Merge that PR to deploy the tested digest through Flux.

GitHub Actions uses its built-in `GITHUB_TOKEN`; no personal publishing token is required in repository secrets. Repository Actions settings must allow Actions to create pull requests. Set the new GHCR package to public for anonymous cluster pulls; a new package starts private. These are one-time GitHub settings.

For upgrades, change both version and commit in `source.json`, review the pinned upstream changes, and merge. CI builds/tests/publishes and proposes the resulting digest. A source pin does not freeze upstream base-image tags or Python dependency resolution; the Deployment digest freezes the actual artifact. Existing builds remain available for rollback.

For additional CLIs or stdio MCP servers, add their installation steps to the local `Dockerfile` before `USER nanobot`, and extend `smoke-test.sh` to check their commands. MCP server configuration and authentication remain runtime settings; do not bake credentials into the image. Standalone HTTP MCP services can be deployed separately and connected through Nanobot configuration. Changes in this directory already trigger the image workflow.

Local build and smoke check on an amd64 Docker host, with the commit from `source.json` checked out at `/path/to/upstream`:

```bash
docker buildx build --builder "$(docker context show)" --load --platform linux/amd64 \
  --build-arg NANOBOT_CHANNELS= --build-arg NANOBOT_EXTRAS= \
  --tag nanobot-upstream:local /path/to/upstream
docker buildx build --builder "$(docker context show)" --load --platform linux/amd64 \
  --build-arg NANOBOT_BASE=nanobot-upstream:local \
  --tag nanobot-custom:local beelink/images/nanobot
bash beelink/images/nanobot/smoke-test.sh nanobot-custom:local
```

Pass the channels/extras from `source.json` if they are nonempty. Debian package versions, including `gh`, resolve at build time; the Deployment digest pins the result.

Do not mount the production SSD for this smoke check. See [maintenance](../../docs/maintenance.md) for deployment operations and [rebuild](../../docs/rebuild.md) for recovery.
