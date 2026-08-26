# Restic backup stack

This stack is intended for the local Docker endpoint and is deployed through
Portainer GitOps from `portainer/restic-backup.yaml`.

## Scope

The container mounts `/data` read-only, but restic is passed exactly these
three paths:

```text
/data/portainer
/data/hindsight
/data/papra
```

The Docker socket is mounted so the backup job can stop and restart exactly
these containers before and after the backup:

```text
papra
hindsight
portainer
```

The monitoring stack is not stopped and none of its data paths are passed to
restic.

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

The restic container mounts `/data` read-only and does not back up the Docker
socket, credentials, images, host OS, Docker engine configuration, or
monitoring data. Papra's `AUTH_SECRET` is a Portainer environment variable and
is intentionally not stored in Git or in the restic Compose file.
