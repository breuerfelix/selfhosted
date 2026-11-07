# Nightly application backups

Each cluster's `shared` Flux Kustomization installs one restic CronJob. It runs at
midnight in Europe/Berlin. The clusters share an S3 bucket, AWS credentials and
a restic password. Each writes to its own repository under its cluster name.

| Cluster | Namespace | Backed-up Deployments |
| --- | --- | --- |
| beelink | nanobot | nanobot |
| beelink | papra | papra |
| hetzner | apps | ghost, fathom |

Each cluster's `shared-sync.yaml` patches the backup ConfigMap with its stable
`RESTIC_HOST` and an `APPS` list of one Deployment per line as `namespace/name`.
The script stops each Deployment in turn, waits for its Pods to disappear,
snapshots `/data/<deployment>` and starts it again before the next. Each snapshot
carries the Deployment name as its tag. The backup Pod mounts the whole `/data`
directory read-only; only the listed Deployments are read. The host directory
must be `/data/<deployment>`; backing up a different layout requires updating
the script before adding the Deployment to `APPS`.

The script checks repository access before stopping anything. Restic retains 7
daily, 4 weekly and 6 monthly snapshots per host/path group and prunes after all
apps restart. One ClusterRoleBinding grants the backup ServiceAccount access to
Deployments and Pods in every namespace.

On failure the Job restarts the Deployment it claimed. After node loss or
SIGKILL, inspect the failed Job and affected Deployment. Restore one replica and
remove the `kustomize.toolkit.fluxcd.io/reconcile` annotation.

## Setup

CronJobs are **enabled** (`suspend: false`). The shared configuration uses
`breuerfelix-k3s-backup` in `eu-central-1`, with separate `beelink/` and `hetzner/`
repositories. Both repositories must exist before deployment.

1. Keep the S3 bucket private with Block Public Access enabled and default SSE-S3
   encryption. Keep objects immediately readable; do not expire current objects,
   transition them to archive storage, or enable Object Lock. Restic owns retention
   and requires deletes. If versioning is enabled, account for retained noncurrent
   versions separately; pruning current objects does not remove old versions.
2. Use one shared IAM credential pair with `iam-policy.json`. The policy permits
   listing only the two repository prefixes and reading, writing and deleting
   their objects. No bucket creation, bucket-wide object access, or KMS
   permissions are needed with SSE-S3.
3. Edit the encrypted credentials from the repository root:

   ```bash
   export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
   sops shared/cluster/backups/credentials.sops.yaml
   ```

   Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and one strong
   `RESTIC_PASSWORD` shared by both repositories. Preserve the password outside
   the clusters as well; losing it makes snapshots unreadable. Root `.sops.yaml`
   encrypts `stringData` for the existing age recipient. Each cluster's `shared`
   Flux Kustomization decrypts using `flux-system/sops-age`.
4. GitHub Actions builds and publishes the amd64 image through
   `.github/workflows/build-backups.yml` on changes to that workflow or
   `shared/images/backups/` on `main`. It can also be run with `workflow_dispatch`.
   It uses the built-in `GITHUB_TOKEN` with `packages: write`; no AWS credentials,
   restic password or SOPS key are supplied to Actions.

   The CronJob uses `ghcr.io/breuerfelix/selfhosted/restic-kubectl:latest` with
   `imagePullPolicy: Always`, so each new backup Pod uses the latest successfully
   published build without a manifest change. The workflow builds the pinned
   upstream images with plain Docker and publishes `latest` and a unique
   `run-<run-id>-<attempt>` tag. It runs only on `main`, without PR checks,
   caching or smoke tests. To roll back, set the CronJob image to a previous
   run tag or digest.

   Renovate automerges kubectl and restic version and digest updates in this
   Dockerfile without waiting for checks. Renovate performs the merge itself
   rather than relying on
   GitHub's auto-merge setting. Keep kubectl compatible with the clusters'
   Kubernetes minor version.

   Make the GHCR package public after its first publication so both clusters can
   pull without registry credentials. Flux and Actions both react to the initial
   push; a Job waiting for the image retries its pull after publication and the
   visibility change. The CronJob remains enabled throughout.
5. Initialize each repository **once**, from a trusted shell with restic and
   SOPS access. These repositories were initialized during setup; use
   `restic cat config` to verify them. For a new, confirmed-empty repository,
   replace that command with `restic init`:

   ```bash
   cluster=beelink # Repeat for hetzner.
   credentials=shared/cluster/backups/credentials.sops.yaml
   export AWS_DEFAULT_REGION=eu-central-1
   export RESTIC_REPOSITORY="s3:https://s3.eu-central-1.amazonaws.com/breuerfelix-k3s-backup/${cluster}/"
   export AWS_ACCESS_KEY_ID="$(sops -d --extract '["stringData"]["AWS_ACCESS_KEY_ID"]' "$credentials")"
   export AWS_SECRET_ACCESS_KEY="$(sops -d --extract '["stringData"]["AWS_SECRET_ACCESS_KEY"]' "$credentials")"
   export RESTIC_PASSWORD="$(sops -d --extract '["stringData"]["RESTIC_PASSWORD"]' "$credentials")"
   restic cat config
   unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
   ```

   A failed connection or wrong password is never a reason to initialize again.
   The nightly script verifies repository access before stopping apps.
6. Validate, then deliver through the normal Git/Flux flow. This enables both
   clusters at once; each cluster's `shared-sync.yaml` sets `RESTIC_HOST` and
   `APPS`.

   ```bash
   kubectl kustomize beelink/cluster >/dev/null
   kubectl kustomize hetzner/cluster >/dev/null
   kubectl kustomize shared/cluster >/dev/null
   sh -n shared/cluster/backups/backup.sh
   ```

## Trigger a backup

Select the matching kubeconfig. Check there is no active backup Job first:
`Forbid` controls scheduled Jobs, not manually created Jobs. Do not overlap a
manual backup with midnight or another manual run.

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
kubectl -n backups get jobs
job="backups-manual-$(date +%s)"
kubectl -n backups create job "$job" --from=cronjob/backups
kubectl -n backups logs -f "job/$job" --pod-running-timeout=120s
kubectl -n backups get job "$job"
```

Use `temp/hetzner-kubeconfig` for Hetzner. A manual Job also runs while its
CronJob is suspended, so finish setup first. Check for one snapshot per target,
application restarts, successful retention and Job completion.

## Restore one application

This example restores Papra on Beelink. Set `suspend: true` in shared
`cronjob.yaml` in Git and push; this pauses both clusters' schedules. Select the
matching kubeconfig and verify that Flux has applied the change. Wait for any
running backup Job to finish before stopping workloads. Keep the CronJob
suspended throughout recovery. For a Hetzner app, use its kubeconfig and the
`apps` namespace instead.

```bash
flux reconcile kustomization shared --with-source
kubectl -n backups get cronjob backups
kubectl -n backups get jobs
```

Stop the target Deployment only; no other application needs to stop. Restore the
desired snapshot and verify the data before starting the Deployment again.

On the **Beelink node**, use a root shell with restic 0.19.1 and kubectl access.
Securely supply the Beelink repository URL, AWS region and three credential
environment variables from setup. Do not put plaintext credentials in Git.
Select an explicit snapshot ID:

```bash
restic snapshots --host beelink --tag papra --path /data/papra
snapshot=REPLACE_SNAPSHOT_ID
kubectl -n papra annotate deployment papra kustomize.toolkit.fluxcd.io/reconcile=disabled
kubectl -n papra scale deployment papra --replicas=0
kubectl -n papra rollout status deployment papra --timeout=300s
kubectl -n papra wait --for=delete pod -l app=papra --timeout=300s
restic restore "$snapshot" --target / --include /data/papra --delete --dry-run -vv
```

Review the dry run. The next command overwrites `/data/papra` and deletes files
there that are absent from the snapshot, including stale database sidecars.
Run only after all Papra Pods are gone. Restic running as root restores numeric
owners and permissions; do not recursively chown or replace the PV/PVC.

```bash
restic restore "$snapshot" --target / --include /data/papra --delete
```

After the restore succeeds, verify the database and documents, then start Papra.

```bash
kubectl -n papra scale deployment papra --replicas=1
kubectl -n papra annotate deployment papra kustomize.toolkit.fluxcd.io/reconcile-
kubectl -n papra rollout status deployment papra --timeout=600s
```

If restoring fails, keep the app stopped until corrected. After verifying the
application, set `suspend: false` in shared `cronjob.yaml`, push and reconcile
`shared`.

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD
```

References: [Flux resource reconciliation](https://fluxcd.io/flux/components/kustomize/kustomizations/#suspend-reconciliation),
[restic S3 permissions](https://restic.readthedocs.io/en/stable/080_examples.html),
[restic retention](https://restic.readthedocs.io/en/stable/060_forget.html),
[restic restore](https://restic.readthedocs.io/en/stable/050_restore.html).
