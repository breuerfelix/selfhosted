# Ghost and Fathom storage

Flux manages two static local PVs and their claims in `hetzner/cluster/infrastructure/storage`. Both claims live in the `apps` namespace. The node is currently named `coolify`, so PV node affinity uses `kubernetes.io/hostname=coolify`. Both PVs/PVCs became Bound through Flux at revision `d419073` on 2026-10-26; no app workloads were started.

| Claim (`apps` namespace) | Local directory on VPS | Declared size | Original Coolify directory |
| --- | --- | --- | --- |
| `ghost-content` | `/srv/k3s-data/ghost` | 10Gi | `/data/coolify/applications/daniel` |
| `fathom-data` | `/srv/k3s-data/fathom` | 1Gi | `/data/coolify/applications/fathom` |

The directories were populated from stopped Coolify containers and verified before these PVs were created. PV capacity is Kubernetes binding metadata; both directories share the VPS root filesystem. These sizes neither reserve disk space nor enforce a quota. Monitor free space on `/`.

Each PV has `persistentVolumeReclaimPolicy: Retain`, `storageClassName: ""`, a `claimRef`, and a local path with required node affinity. Each PVC has `storageClassName: ""` and `volumeName`, which prevents K3s's default `local-path` class from dynamically creating another volume. Deleting a PVC does not delete the local files. Reusing a released PV with a new PVC may require clearing its stale `claimRef` after confirming the correct data path; never delete files as part of that operation.

For a fresh VPS, first recreate the two directories using `hetzner/ansible/storage.yml` and restore their contents from backup. Keep node hostname `coolify` or update the PV node affinity in Git. Then bootstrap Flux and verify:

```bash
KUBECONFIG=temp/hetzner-kubeconfig kubectl get pv ghost-content fathom-data
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get pvc ghost-content fathom-data
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps describe pvc ghost-content fathom-data
```

Both claims must be `Bound` to their named PVs before starting Ghost or Fathom. `Retain` is not a backup. Preserve Mac archive and old Coolify directories until restore is tested.

Screeps uses a separate 3Gi `local-path` PVC named `apps/screeps-data`. It is Bound and contains a fresh world; no old Screeps data was copied. Its local-path provisioner directory is managed by K3s and is not part of the Ghost/Fathom backup. On a fresh cluster, let Flux recreate the claim and let Screeps start empty. PVC size is not a filesystem quota on this host.
