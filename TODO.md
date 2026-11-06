# TODO

- [x] Implement nightly application backups with shared restic base and per-cluster Flux patches. See [setup and restore instructions](shared/cluster/backups/README.md).
- [x] Configure the shared S3 bucket/region and encrypted credentials, initialize and check both restic repositories, and prepare the GitHub Actions image build with enabled CronJobs.
- [ ] Push the prepared changes, verify the backup image publishes and its GHCR package is public, then confirm Flux deployment and the first nightly backup in both clusters. This is the accepted backup policy; no ad hoc volume backups are required before changes or rollouts.
