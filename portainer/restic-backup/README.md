# Restic backup stack

This stack is intended for the local Docker endpoint and is deployed through
Portainer GitOps from `portainer/restic-backup.yaml`.

## Scope

The container mounts and backs up only these three Docker paths, read-only:

```text
/data/portainer
/data/hermes-backup
/data/hindsight
```

The Hermes stack mounts the host path `/data/hermes-backup` at
`/opt/data/backups`. The Hermes cron backup job writes its ZIP archives there,
and the restic job captures that directory as a separate backup source.

Before redeploying the Hermes stack, create the host directory with ownership
matching the Hermes container's runtime user. The current image runs as
UID/GID `10000:10000`:

```bash
sudo install -d -o 10000 -g 10000 -m 0700 /data/hermes-backup
```

If `/data/hermes/backups` already contains archives that should be retained,
copy them to `/data/hermes-backup` before redeploying. The new bind mount hides
the old directory from the Hermes container.

The Docker socket is mounted so the backup job can stop and restart exactly
these containers before and after the backup:

```text
hindsight
portainer
```

K3s applications are excluded. This stack has no K3s data mounts, Kubernetes
credentials, or Kubernetes lifecycle hooks.

## Portainer environment variables

Set these in the Portainer stack environment before deploying:

```text
RESTIC_REPOSITORY=s3:s3.amazonaws.com/<bucket>/hosts/<host>/portainer
RESTIC_PASSWORD=<long random restic repository password>
AWS_ACCESS_KEY_ID=<S3 access key>
AWS_SECRET_ACCESS_KEY=<S3 secret key>
AWS_DEFAULT_REGION=eu-central-1
```

If the AWS credential is temporary, also set `AWS_SESSION_TOKEN`.

Do not commit any of these values to Git. The restic repository password must
be stored separately from the S3 credentials and retained offline; losing it
makes the encrypted repository unrecoverable.

## Initial setup

The scheduled job intentionally does not initialize a repository. After the
S3 variables are configured, initialize it once from the running container:

```bash
docker exec restic-backup restic init
```

Run one manual backup and inspect the logs before relying on the scheduler:

```bash
docker exec restic-backup /usr/local/bin/backup.sh
docker logs --since 10m restic-backup
```

The backup is scheduled for `03:00` in `Europe/Berlin`. Repository pruning runs
at `03:30` on Sundays, and a 5% data check runs at `04:00` on Sundays.

Retention is:

```text
7 daily, 4 weekly, 6 monthly, 3 yearly snapshots
```

## Restore test

List snapshots:

```bash
docker exec restic-backup restic snapshots
```

Restore to a temporary host directory rather than directly over live state:

```bash
mkdir -p /var/tmp/restic-restore-test
docker exec restic-backup \
  restic restore latest --target /var/tmp/restic-restore-test
```

The restic container does not back up the Docker socket, credentials, images,
host OS, Docker engine configuration, or K3s applications. K3s application
backups are disabled for now.
