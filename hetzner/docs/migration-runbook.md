# Migration runbook and current state

Last verified: 2026-10-26, Europe/Berlin. Read this before any server action. Host alias is `ssh cool`; SSH session ran as root. Repository workspace on Mac: `/Users/felix/code/selfhosted`.

## Current checkpoint

**Coolify and all Docker application containers are stopped. K3s is running and enabled at boot. Flux is reconciling `main`; Ghost/Fathom PVs and PVCs are Bound. Ghost, Fathom, and Noobgallery run at one replica each. K3s-packaged Traefik and ServiceLB are running; cert-manager and four production Certificates are Ready.** Ghost, Fathom, Noobgallery, and `felixbreuer.me` redirect are public over HTTPS. Screeps remains inactive and has no route. All 13 old Docker containers had restart policy changed to `no`, so reboot will not restart them. K3s node and core deployments were Ready. SSH and Docker daemon remained available. Ghost/Fathom data exists under `/srv/k3s-data`; original Coolify folders and Mac archive remain intact. Ubuntu updates run at 01:00/02:00 Berlin time with conditional reboot at 03:00; see [ubuntu-updates.md](ubuntu-updates.md).

Original server data remains in place:

- Ghost: `/data/coolify/applications/daniel` (about 2.7 GB).
- Fathom: `/data/coolify/applications/fathom` (about 2.8 MB).
- Screeps: `/data/coolify/applications/screeps` (about 949 MB at last check; not backed up by agreement).

**Ghost and Fathom were copied into `/srv/k3s-data`; both retained local PVs and PVCs are Bound. K3s, Flux, three app Deployments, and one Traefik redirect route are running. No Coolify data or containers were deleted.**

## Completed actions, in order

1. Inspected repo and VPS read-only. Repo remote: `git@github.com:breuerfelix/selfhosted.git`; current branch was `main`. VPS: Ubuntu 24.04, 4 CPUs, 8 GB RAM, 75 GB root filesystem, about 42 GB free before migration. Coolify ran seven applications; its proxy owned ports 80/443.
2. User upgraded and rebooted Ubuntu. Post-reboot check found Docker and all Coolify containers running. No K3s service existed.
3. Created root `.gitignore` entry `/temp/` and local `/Users/felix/code/selfhosted/temp/coolify-migration/`. Verified Git ignores files there. Root `.gitignore` was committed with host and Flux configuration in `097e010`.
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
15. Generated Flux v2.9.6 manifests under `hetzner/cluster/` with only source, Kustomize, and Helm controllers. Its Git source uses anonymous HTTPS for this public GitHub repository and has no `secretRef`. `kubectl kustomize hetzner/cluster` rendered successfully; `.gitignore` kept Mac backup and kubeconfig out of Git. Committed all host/bootstrap files as `097e010` and pushed `main`.
16. Applied Flux components, waited for GitRepository and Kustomization CRDs, then applied the sync objects. All three controller deployments rolled out. `flux check` passed, and source plus Kustomization were Ready at `main@sha1:097e0104`. No application workloads were deployed. See [flux-bootstrap.md](flux-bootstrap.md) for recovery steps.
17. Added static `local` PVs and PVCs for Ghost (`10Gi`) and Fathom (`1Gi`) under `hetzner/cluster/infrastructure/storage`, plus the `apps` namespace. Prebound by name, excluded default `local-path` class with `storageClassName: ""`, set `Retain`, and pinned node affinity to `kubernetes.io/hostname=coolify`. Pushed commit `d419073`; Flux reported Ready at that revision. Both PVCs and PVs reached `Bound`; `apps` had no pods/deployments. Rechecked data directory sizes (`2.7G` Ghost, `2.8M` Fathom) and ownership. See [storage.md](storage.md).
18. Copied the nonempty Screeps config to ignored `temp/screeps-config.yml` and generated an age identity at ignored `temp/hetzner-sops-age.key` (mode `0600`). The key must be copied into a password manager by the user. Encrypted Screeps config in Git, validated local decryption against the original, and manually installed matching key as `flux-system/sops-age`. Added SOPS decryption to Flux's Git-managed Kustomization. Removed temporary plaintext Screeps config/Secret and redirect environment copies afterward; original Coolify files remain. See [secrets.md](secrets.md).
19. Prepared seven app Deployment/Service directories under `hetzner/cluster/apps/`, each with an image digest pin. The three images with version tags use them; four images that only publish `latest`/`main` use `latest@sha256` pins. Updated Renovate's Kubernetes manager pattern. App directories are not in root cluster Kustomization, so nothing starts. Rendered and server-dry-run validated manifests; Screeps encrypted Secret was decrypted only for validation. See [app-preparation.md](app-preparation.md).
20. User retired Travian inactive finder and idle proxy. Removed their two inactive K3s manifest directories and excluded both routes from the migration plan. Five app directories remain. Old Coolify containers and legacy definitions were kept for history/rollback; they remain stopped and will not be started by the rollback commands below.
21. Rechecked both PVC bindings, stopped old Docker containers, 39 GB free space, Mac backup SHA-256, and copied SQLite `integrity_check=ok`. Added only `./apps/ghost` and `./apps/fathom` to root Kustomization and pushed commit `9fdc994`. Flux applied it; both Deployments became 1/1 Ready with zero restarts. Internal port-forward requests returned HTTP 200 for both Services; an existing Ghost image returned HTTP 200 with `image/jpeg` and 476031 bytes. Ghost copied DB retained 30 posts, 149 tags, and 2 users, matching old DB; Fathom retained 3 sites and 1 user. Both copied DBs still passed `integrity_check=ok`. Ghost logged nonfatal theme validation/translation warnings; Fathom logged a missing `.env` warning but connected to SQLite and listened on 8080. Port-forward processes were stopped afterward. No ingress exists.
22. Added only `./apps/redirect` and `./apps/noobgallery` to root Kustomization and pushed commit `6d61d63`. Flux applied it; both Deployments reached 1/1 Ready with zero restarts. Via local port-forward, redirect returned HTTP 301 with `Location: http://breuer.dev/`, matching recovered Coolify `PROTOCOL=http` and `REDIRECT_TO=breuer.dev`. Noobgallery returned HTTP 200 for its homepage, one gallery JPEG, and CSS. Port-forward processes were stopped. No ingress exists; public routes remain offline.
23. Changed plan to use K3s-packaged Traefik. Removed `disable: traefik` from Ansible-managed K3s config and made `k3s.yml` restart the active service only if config changes. Dry run showed only the config change and planned restart; the pinned bootstrap installer was skipped. Applied playbook. K3s node returned Ready; packaged HelmChart `traefik` installed chart `40.1.5+up40.1.0`, with Traefik image `3.7.13`. Initial Helm job retried after CRDs became available, then completed. Traefik Deployment reached 1/1, ServiceLB DaemonSet reached 1/1, and LoadBalancer Service advertised `91.99.161.123` on 80/443. Public HTTP with an unknown Host returned 404. No Ingress exists, so apps remain unexposed. Four app Deployments stayed 1/1, Ghost/Fathom PVCs Bound, Flux Ready, and Docker running count zero. No custom `HelmChartConfig` is needed at this point; Traefik version follows K3s.
24. Added cert-manager through Flux's `OCIRepository` and `HelmRelease`, using chart `v1.21.3` and digest-pinned controller, webhook, cainjector, solver, and startup API check images. Enabled chart CRDs. Rendered chart and root Kustomization, then pushed commit `ad4a85a`. Flux applied it. OCI source and HelmRelease became Ready, all three Deployments reached 1/1 with zero restarts, six cert-manager CRDs appeared, and API discovery succeeded. Four apps remained 1/1; Ghost/Fathom PVCs remained Bound. No Ingress or issuer was created; public HTTP still returned 404. See [cert-manager.md](cert-manager.md).
25. Verified DNS A records for `danielkueffler.de`, `stats.felixbreuer.me`, `photos.felixbreuer.me`, and `felixbreuer.me` resolve to `91.99.161.123`, with no AAAA records returned. Public port 80 reached Traefik for each. Added production `ClusterIssuer/letsencrypt-prod`, shared HTTP-to-HTTPS Middleware, and Ghost HTTPS/HTTP Ingresses in commit `b805b94`. Ghost certificate became Ready; public HTTP redirected to HTTPS, and HTTPS returned 200 with a valid Let's Encrypt certificate. User then specified ACME contact `felix@breuer.dev` and HTTPS target for the redirect; issuer email was updated in Git.
26. Added Fathom, Noobgallery, and `felixbreuer.me` Ingresses in commit `6efeaee`. Their certificates became Ready. Fathom and Noobgallery returned 200 over HTTPS, and HTTP redirected to HTTPS. Redirect container ignored `PROTOCOL=https` because its nginx config built Location from `$scheme`, so public HTTPS still pointed to `http://breuer.dev/`. Its Deployment had rolled out with the new env value; this was an image behavior, not a Flux delay.
27. Replaced redirect container with Traefik `RedirectRegex` Middleware plus HTTP/HTTPS `IngressRoute` objects backed by `noop@internal`. Issued an explicit new Certificate first in commit `b1a50a3`, then removed obsolete redirect Deployment, Service, and Ingresses in commit `f4ffc7b`. Flux pruned them. The old `redirect-tls` Secret was deleted after its Certificate and Ingress disappeared; new `felixbreuer-me-tls` is Ready. Both `http://felixbreuer.me/path?x=1` and `https://felixbreuer.me/path?x=1` now redirect to `https://breuer.dev/path?x=1`. All three remaining app Deployments are 1/1 and Ghost/Fathom PVCs Bound. See [ingress.md](ingress.md).

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

Pause here. Three applications and a native redirect are verified publicly with four production certificates; Screeps remains inactive. User must store `/Users/felix/code/selfhosted/temp/hetzner-sops-age.key` in a password manager. Next proposed checkpoint: review and activate Screeps with its encrypted config and disposable local volume, then add its route and certificate if healthy. Reboot recovery, ongoing backups, and automatic K3s upgrades remain later stages. Keep old Coolify directories and Mac archive intact.

## Rollback to Coolify

First remove active `./apps/*` entries from `hetzner/cluster/kustomization.yaml`, push, and wait for Flux to remove K3s workloads and routes. Keep `./flux-system` and `./infrastructure/storage` entries. Then release ports 80/443: add `disable: [traefik]` to the Ansible-managed K3s config in `hetzner/ansible/k3s.yml`, apply that playbook, and verify Traefik ServiceLB pods are gone before starting Coolify proxy. Commit the rollback config so a future Ansible run does not re-enable Traefik. Existing Docker containers and data must remain untouched for this procedure. Commands below restore restart policies and start only the five retained apps plus Coolify; retired inactive finder and idle proxy stay stopped. Run from `ssh cool` as root. Container names were verified on 2026-10-25; inspect before use if state has changed. Coolify will use its original directories, so any writes made only to K3s copies after activation are not automatically carried back.

```bash
docker update --restart=always coolify coolify-realtime coolify-db coolify-redis
docker update --restart=unless-stopped \
  screeps coolify-proxy danielkueffler fathom \
  hk800wo04cg40kskco04g8k4-182621145125 \
  tcwk0w00ssookk84w8880oog-150844045641
docker start coolify-db coolify-redis
docker start coolify coolify-realtime coolify-sentinel
docker start danielkueffler fathom screeps \
  hk800wo04cg40kskco04g8k4-182621145125 \
  tcwk0w00ssookk84w8880oog-150844045641
docker start coolify-proxy
docker ps --format '{{.Names}} {{.Status}}'
```

`coolify-sentinel` originally had restart policy `no`; command above leaves it that way. Source data is already at original Coolify paths. Verify public routes after rollback.

## Future implementation stages

1. Activate Screeps separately with its unbacked-up local-path storage and SOPS-encrypted config; verify its fresh server before adding public route. Inspect a failed start before changing config or image version.
2. Reboot VPS once and verify automatic recovery of K3s, Flux, certificates, and all workloads/routes. Configure and test ongoing Mac backup. Only then remove Coolify containers and old files; keep migration archive until restore is tested.
3. Add automatic K3s patch upgrades with a maintenance window separate from Ubuntu's reboot window.
