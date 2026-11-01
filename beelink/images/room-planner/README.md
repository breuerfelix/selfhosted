# Room Planner image

`source.json` records the pinned source revision, original Node base,
live generated lockfile hash, immutable build commit, image digest, and CI run.
The source repository is private; the image remains private.

Build recipe lives at the exact `buildCommit` in
`breuerfelix/screeps-room-planner`, branch `codex/k3s-room-planner`.
That branch starts at the running version, not upstream main. Its only changes
are the captured lockfile, digest-pinned Dockerfile with frozen installation,
and pinned Actions workflow with a no-network UI/proxy smoke test. Dispatch
`room-planner-image.yml` on this branch to reproduce the build. Do not merge this
old application branch over current upstream main.

Build tags are `k3s-<full-build-commit>`; deployment always pins the tested digest.
A future rebuild must pass smoke tests and receive an explicit digest update.
Review dependency and frontend API URL changes before updating the build.

Configure private registry access using a token with `read:packages` and access
to this package:

```bash
python3 beelink/scripts/configure-room-planner-registry.py
```

The helper verifies access to the exact pinned digest, keeps credentials in
memory, writes only a SOPS-encrypted Secret using the existing Beelink recipient,
and adds it to Kustomize. It does not change Flux suspension or the cluster.
A token already stored in a protected local file can be passed through
`--token-file /absolute/path`. Never pass the token itself as an argument.

The Flux sync remains suspended. Application fixes and registry access are required before enabling it.
