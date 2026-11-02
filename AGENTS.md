# Repository guidance

Favor simplicity and reduce complexity. Use plain manifests and upstream defaults; add configuration or abstractions only when a current requirement needs them.

`beelink` and `hetzner` are permanently single-node clusters. Do not add pod node selectors, affinities, topology spread constraints, or other multi-node scheduling configuration. Retained static storage uses `hostPath` PVs with `type: Directory`, explicit claims, and `Retain`; preserve existing data paths and ownership.

Do not create volume backups or require ad hoc backups before changes or rollouts. The planned nightly AWS S3 backups are the accepted backup policy; implementation is tracked in `TODO.md`.
