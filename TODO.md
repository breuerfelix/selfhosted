# TODO

- [ ] Migrate the Hetzner Screeps server from dynamically provisioned `local-path` storage to a static PersistentVolume with a fixed host directory and `persistentVolumeReclaimPolicy: Retain`. Keep host data cleanup manual, including after namespace deletion. The current PVC is in `hetzner/cluster/apps/screeps/storage.yaml`; until migration, deleting it or its namespace can delete its provisioned host data, depending on the live PV reclaim policy and provisioner configuration.
