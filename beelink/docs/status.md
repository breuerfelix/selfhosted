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

The nanobot Kustomization remains suspended. No nanobot pod or persistent volume is created by this step. The existing Docker subnet router and all Docker apps remain in place.

## Pending

1. Prepare/test the upstream nanobot image workflow, publish its image, and commit its digest/pull policy into the Deployment. Current local-image settings are fallback placeholders.
2. Stop both Docker nanobot writers before enabling the nanobot sync and validating cutover, including HTTPS and WebSocket behavior through Tailscale.

No application migration has occurred.
