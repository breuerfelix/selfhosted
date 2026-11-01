# Beelink K3s

Single-node K3s on `ssh bee`, managed by Flux from this repository. First app: nanobot gateway plus its built-in web UI. The separate nanobot API is retired at cutover. Other Docker workloads stay running.

**Nanobot migrated on 31 October 2026.** K3s, Flux, and the Tailscale operator are Ready. Nanobot runs from a tested GitHub Actions build of pinned upstream sources, using its original SSD mount. Open [nanobot](https://nanobot.vulture-skink.ts.net/) with Tailscale connected and use the existing WebUI password. Both old Docker nanobot containers are stopped with restart disabled. The old Docker subnet router was also stopped on 1 November after Pi-hole joined Tailscale directly; unrelated Docker apps remain running. See [verified status](docs/status.md), [image build](images/nanobot/README.md), [authentication steps](docs/tailscale.md), and [the bootstrap and cutover runbook](docs/bootstrap.md).

```text
beelink/
  ansible/                    # Host bootstrap and SSD checks
  cluster/flux-system/        # Independent Flux installation and Git source
  cluster/infrastructure/     # Tailscale Helm release; encrypted OAuth Secret added at setup
  cluster/apps/nanobot/       # Deployment, Service, retained local PV/PVC, private ingress
  cluster/*-sync.yaml         # Staged Flux reconciliation
  images/nanobot/             # Upstream source pin, image smoke test, digest update helper
  scripts/                    # Local SOPS credential helper
  templates/                  # Credential template, never a filled plaintext secret
  .sops.yaml                  # Same public age recipient as Hetzner
```

All application persistence uses static retained local PVs at each app's existing Docker bind-mount source path. Nanobot keeps `/data/nanobot` mounted at `/home/nanobot/.nanobot`. No copying, formatting, replacement storage tree, or recursive ownership change is part of migration. K3s state and container images use the internal system disk at `/var/lib/rancher/k3s`.

Tailscale provides private HTTPS for the nanobot UI. Pi-hole runs separately and provides tailnet DNS. Flux reads public GitHub over HTTPS; it does not require a GitHub token. The Tailscale operator's OAuth credentials are encrypted with SOPS. GitHub Actions builds/publishes images with its built-in token; the GHCR package is public for anonymous cluster pulls.
