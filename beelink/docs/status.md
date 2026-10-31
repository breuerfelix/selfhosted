# Bootstrap status

31 October 2026: executed `ansible/k3s.yml` against `ssh bee`.

- K3s `v1.36.5+k3s1`, bundled containerd `2.3.4-k3s1.36`.
- Node `beelink` Ready at `192.168.178.13`, using `enp1s0`.
- Service active and enabled at boot. `/data` mount dependency loaded from the existing fstab; UUID check installed before K3s startup.
- Traefik, ServiceLB, and dynamic local-storage disabled. No StorageClass installed.
- CoreDNS and metrics-server ready; API `/readyz` returns `ok`.
- Temporary BusyBox pod successfully pulled its image, resolved Kubernetes service DNS and `ghcr.io`, and reached the internet over HTTP. Test pod removed.
- All 17 Docker containers retained their IDs and start timestamps. Nanobot gateway health, its web UI, and Grafana health returned HTTP 200.
- Second Ansible run: `changed=0`, `failed=0`.
- Private kubeconfig saved at ignored `temp/beelink-kubeconfig`, mode `0600`, context `beelink`. Direct access from the Mac verified. Global kubeconfig unchanged.

No reboot was performed; the mount dependency and its successful startup checks were inspected in the running systemd manager, not by interrupting the SSD or host. No app data, Docker restart policies, tailnet settings, or remote Git branches were changed.

## Flux and Tailscale

Flux source, Kustomize, and Helm controllers are installed. The public Git source uses `main` and root path `./beelink/cluster`. The existing Hetzner age identity is installed as `flux-system/sops-age`.

Tailscale authentication completed on 31 October 2026. `operator-oauth.sops.yaml` is encrypted with the same age recipient as Hetzner; Flux decrypts it into `tailscale/operator-oauth`. The `tailscale` Kustomization and `tailscale-operator` HelmRelease are Ready. The operator pod is running and tailnet status confirms `beelink-k8s-operator` is online with `tag:k8s-operator`, at `beelink-k8s-operator.vulture-skink.ts.net`. MagicDNS and HTTPS certificate support are enabled. No plaintext credential file was created during validation or publication.

This verifies operator enrollment, not application ingress. There is no app proxy or nanobot HTTPS endpoint yet. Future credential setup/rotation is described in [authentication steps](tailscale.md).

## Nanobot migration

Nanobot is enabled in Flux and running as one Ready pod with UID:GID `1000:1000`. Its retained local PV/PVC is Bound to the original `/data/nanobot`, mounted at `/home/nanobot/.nanobot`. No data was moved or recursively chowned.

- [GitHub Actions build](https://github.com/breuerfelix/selfhosted/actions/runs/41233500975) passed, including an isolated non-root gateway/WebUI test with disposable state and no network.
- Upstream `v0.4.0`, commit `8f7a7d17590de7ab187650381894dba2b9e060ab`, built directly with its Dockerfile. The current source/build parameters live in `images/nanobot/source.json`.
- [Image digest PR #152](https://github.com/breuerfelix/selfhosted/pull/152) merged. The actual image digest is pinned in `cluster/apps/nanobot/app.yaml`; the package is public and K3s pulled it anonymously.
- Tailscale proxy is Ready. [Nanobot HTTPS](https://nanobot.vulture-skink.ts.net/) returned HTTP 200 from the Mac with certificate verification enabled. Gateway health returned HTTP 200 inside the pod.
- `config.json` matches the stopped-writer backup exactly; existing workspace, sessions, and usage database are present. The existing WebUI password remains unchanged. No real model/tool request was sent during validation.
- Portainer GitOps updates for stack 41 were already disabled. Both `nanobot` and `nanobot-api` Docker containers are stopped with restart policy `no`, retained for rollback. Do not manually redeploy/start this old stack while Kubernetes owns the mount.
- All 15 other Docker containers retained their IDs and start timestamps. The old Docker Tailscale subnet router remains running.
- Consistent pre-cutover archive: `/var/backups/nanobot-before-k3s-20261031T192254Z.tar.gz` on `bee`, mode `0600`. Both writers were stopped before archiving; archive readability was checked. This local archive supplements existing off-host backups.

GitHub Actions is allowed to create the workflow's digest-update PRs; default workflow permissions remain read-only, with explicit per-job permissions in YAML. Future builds do not change nanobot's suspension state. Review and merge their digest PRs to deploy.

## Pending

Verify the user's ongoing off-host nanobot backup method against the Kubernetes writer. The repository's existing Docker Restic job does not include nanobot. A controlled host reboot/recovery drill and a real provider/tool request remain separate checks.
