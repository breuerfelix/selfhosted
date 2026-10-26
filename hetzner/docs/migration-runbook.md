# Migration runbook and current state

Last verified: 2026-10-26, Europe/Berlin. Read this before any server action. Host alias is `ssh cool`; SSH session ran as root. Repository workspace on Mac: `/Users/felix/code/selfhosted`.

## Current checkpoint

**Coolify and all application containers are stopped. K3s is running and enabled at boot.** Public applications are offline intentionally. All 13 Docker containers had restart policy changed to `no`, so reboot will not restart them. `docker ps` returned zero running containers. K3s node and CoreDNS, local-path-provisioner, metrics-server were Ready. SSH and Docker daemon remained available. Ghost/Fathom data exists under `/srv/k3s-data`; original Coolify folders and Mac archive remain intact. Ubuntu updates run at 01:00/02:00 Berlin time with conditional reboot at 03:00; see [ubuntu-updates.md](ubuntu-updates.md).

Original server data remains in place:

- Ghost: `/data/coolify/applications/daniel` (about 2.7 GB).
- Fathom: `/data/coolify/applications/fathom` (about 2.8 MB).
- Screeps: `/data/coolify/applications/screeps` (about 949 MB at last check; not backed up by agreement).

**Ghost and Fathom were copied into `/srv/k3s-data`. K3s cluster is running; Flux and app/PV manifests are not deployed. No Coolify data or containers were deleted.**

## Completed actions, in order

1. Inspected repo and VPS read-only. Repo remote: `git@github.com:breuerfelix/selfhosted.git`; current branch was `main`. VPS: Ubuntu 24.04, 4 CPUs, 8 GB RAM, 75 GB root filesystem, about 42 GB free before migration. Coolify ran seven applications; its proxy owned ports 80/443.
2. User upgraded and rebooted Ubuntu. Post-reboot check found Docker and all Coolify containers running. No K3s service existed.
3. Created root `.gitignore` entry `/temp/` and local `/Users/felix/code/selfhosted/temp/coolify-migration/`. Verified Git ignores files there. Root `.gitignore` is currently an **uncommitted** repository change.
4. Saved container names and original restart policies locally to `temp/coolify-migration/container-names.txt` and `temp/coolify-migration/restart-policies.txt`.
5. Changed all 13 Docker container restart policies to `no`, then stopped all containers. Some exited after Docker's timeout; all are now stopped. Original containers and application directories remain available for rollback.
6. With containers stopped, streamed Ghost and Fathom directories into `temp/coolify-migration/ghost-fathom.tar` on this Mac. Archive size is about 2.7 GB and contains 1,873 entries. Created `ghost-fathom.tar.sha256`.
7. Verified archive SHA-256, readable tar entries, Ghost media paths, and both SQLite databases using `PRAGMA integrity_check` (`ok` for each). Extracted DB hashes matched server originals exactly.
8. Rechecked host: zero running Docker containers, all restart policies `no`, no K3s service, old source directories present.
9. On 2026-10-26, created `hetzner/ansible/ubuntu-updates.yml` and applied it to `cool`. It changed host timezone to `Europe/Berlin`, rescheduled package-list refresh for 01:00 and unattended upgrades for 02:00, and enabled conditional automatic reboot at 03:00. Effective timers and APT settings were verified; a second Ansible run reported `changed=0`. No upgrade or reboot was triggered manually.
10. On 2026-10-26, applied `hetzner/ansible/storage.yml` to create `/srv/k3s-data/ghost` (UID:GID `1000:0`) and `/srv/k3s-data/fathom` (`0:0`). Ansible rerun reported `changed=0`. With all containers stopped, used `rsync -aHAX --numeric-ids` to copy from `/data/coolify/applications/daniel/` and `/data/coolify/applications/fathom/`. No source files were moved or deleted; no Screeps data was copied.
11. Verified copied data: `rsync -aHAXnc --itemize-changes` showed no differences for either tree, Ghost/Fathom SQLite SHA-256 hashes matched source and Mac archive, and Python SQLite `PRAGMA integrity_check` returned `ok` for both copies. Host had zero running Docker containers and about 40 GB free afterward.
12. Staged K3s `v1.36.5+k3s1` through `hetzner/ansible/k3s.yml`, with bundled Traefik disabled and server public IPv4 in TLS SAN. Official installer was run with `INSTALL_K3S_SKIP_ENABLE=true` and `INSTALL_K3S_SKIP_START=true`. Verified `k3s` service was disabled/inactive and no process listened on 6443. Ansible rerun reported `changed=0`. No cluster has been started; Hetzner Cloud Firewall setup is pending user confirmation.
13. User reported Hetzner Cloud Firewall attached, with TCP 22 and TCP 6443 currently allowed from anywhere; user plans to tighten these later. Opened a new SSH TCP connection successfully. Then ran `hetzner/ansible/k3s-start.yml -e firewall_verified=true`: K3s service became enabled/active and node `coolify` reached Ready at `v1.36.5+k3s1`. Rerun reported `changed=0`.
14. Copied root-only `/etc/rancher/k3s/k3s.yaml` to Mac `temp/hetzner-kubeconfig`, changed server URL to `https://91.99.161.123:6443`, and set file mode `0600`. Git ignores it. `kubectl get nodes` from Mac passed TLS and showed Ready; CoreDNS, local-path-provisioner, and metrics-server deployments all became 1/1 Available. Port 80/443 still had no listener, and Docker running count remained zero. No reboot test yet.

Archive SHA-256:

```text
5e0076127e4a57c60a808e7d39d8033fec27408dacd819e6f39bbf10e0c7c08e  temp/coolify-migration/ghost-fathom.tar
```

SQLite SHA-256 hashes (local extracted copies matched source files):

```text
32f8e47ca4acfe661b2de6a438b56ed99deb502b99f1c1f0cd97c2bff5c15b65  daniel/data/ghost.db
f93bc6b89d704486e521af0cdaa61c2550baa9efa73042a348220b9d88f7e1e0  fathom/fathom.db
```

Local archive and policy files are **ignored by Git**. A fresh checkout or another computer will not contain them. Do not delete `temp/` until migration and restore validation are complete.

## Immediate next stage

Pause here. Review Flux bootstrap plan and repository authentication with user before deployment. Then create Flux manifests under `hetzner/cluster/`, bootstrap against this Git repo, and verify reconciliation. Static PV/PVC and application deployment remain later checkpoints. Keep old Coolify directories and Mac archive intact.

## Rollback to Coolify

If K3s ingress has already taken ports 80/443, release those ports first. Existing Docker containers and data must remain untouched for this procedure. Commands below restore recorded restart policies and start prior stack; run from `ssh cool` as root. Container names were verified on 2026-10-25; inspect before use if state has changed.

```bash
docker update --restart=always coolify coolify-realtime coolify-db coolify-redis
docker update --restart=unless-stopped \
  screeps coolify-proxy danielkueffler fathom \
  hk800wo04cg40kskco04g8k4-182621145125 \
  tcwk0w00ssookk84w8880oog-150844045641 \
  qw08wsg44cgossk8sg0sws8k-112020026593 \
  wwgk8sgck44gocwscc0gs4ck-111920518419
docker start coolify-db coolify-redis
docker start coolify coolify-realtime coolify-sentinel
docker start danielkueffler fathom screeps \
  hk800wo04cg40kskco04g8k4-182621145125 \
  tcwk0w00ssookk84w8880oog-150844045641 \
  qw08wsg44cgossk8sg0sws8k-112020026593 \
  wwgk8sgck44gocwscc0gs4ck-111920518419
docker start coolify-proxy
docker ps --format '{{.Names}} {{.Status}}'
```

`coolify-sentinel` originally had restart policy `no`; command above leaves it that way. Source data is already at original Coolify paths. Verify public routes after rollback.

## Future implementation stages

1. Extend idempotent host provisioning under `hetzner/ansible/`: required packages, persistent directories, K3s configuration and pinned install. Ubuntu time/update settings are already managed there. Keep SSH access and guard API port 6443.
2. Install K3s; verify systemd boot enablement and node readiness. Use single-server SQLite. Disable bundled Traefik if installing Flux-managed Traefik.
3. Bootstrap Flux against this repository with sync path under `hetzner/cluster/`. Store Git deploy credentials and SOPS age identity outside Git for recovery.
4. Deploy infrastructure and seven applications through Flux. Use deterministic retained local PVs for Ghost/Fathom. Migrate Screeps configuration; recover redirect values from old runtime configuration. Keep stateful apps at one replica and use `Recreate` strategy for SQLite-backed apps.
5. Configure ingress and automatic TLS. Verify every public route and Ghost/Fathom data. Reboot VPS once and verify automatic recovery.
6. Configure and test ongoing Mac backup if selected. Only then remove Coolify containers and old files. Keep backup archive until full restore has been tested.
