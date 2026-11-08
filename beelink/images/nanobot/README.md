# Nanobot image build

`.github/workflows/build-nanobot.yml` pins the upstream release tag, builds the upstream Dockerfile unchanged, then builds this directory's `Dockerfile` on top to add GitHub CLI (`gh`) and run as `nanobot`.

Changes to the workflow or this directory on `main` build and publish `latest` and a unique `run-<run-id>-<attempt>` tag to GHCR. The workflow can also be run manually on `main`. Both builds use plain Docker on an amd64 runner, without caching or smoke tests. Publishing uses the built-in `GITHUB_TOKEN`; keep the GHCR package public for cluster pulls.

Renovate opens upstream release PRs updating `NANOBOT_REF` in the workflow. After a build publishes `latest`, Renovate opens a separate PR updating the Deployment's `latest@sha256:…` digest. Merge that PR to deploy through Flux. For rollback, restore a previous digest in Git.

Add CLI or stdio MCP dependencies to the local `Dockerfile` before `USER nanobot`. Authentication and MCP configuration remain runtime settings.

Local build on an amd64 Docker host, using the `NANOBOT_REF` tag from the workflow:

```bash
docker build --tag nanobot-upstream:local \
  --build-arg NANOBOT_CHANNELS= --build-arg NANOBOT_EXTRAS= \
  "https://github.com/HKUDS/nanobot.git#v0.4.0"
docker build --tag nanobot-custom:local beelink/images/nanobot
```

The empty channels/extras override upstream's default WhatsApp dependencies. Upstream base images, Python dependencies, and Debian packages resolve at build time; the Deployment digest pins the result.

See [maintenance](../../docs/maintenance.md) for deployment operations and [rebuild](../../docs/rebuild.md) for recovery.
