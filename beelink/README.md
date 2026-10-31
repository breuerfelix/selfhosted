# Beelink K3s

Single-node K3s on `ssh bee`, managed by Flux from this repository. First app: nanobot gateway plus its built-in web UI. The separate nanobot API is retired at cutover. Other Docker workloads stay running.

**K3s bootstrapped on 31 October 2026.** Node `beelink` is Ready; Traefik, ServiceLB, and dynamic local storage are disabled. Existing Docker containers remain running. Flux manages the Tailscale operator; it waits for OAuth credentials before becoming Ready. Kubernetes nanobot remains suspended. See [verified status](docs/status.md), [authentication steps](docs/tailscale.md), [the design](docs/design.md), and [the bootstrap and cutover runbook](docs/bootstrap.md).

```text
beelink/
  ansible/                    # Host bootstrap and SSD checks
  cluster/flux-system/        # Independent Flux installation and Git source
  cluster/infrastructure/     # Tailscale Helm release; encrypted OAuth Secret added at setup
  cluster/apps/nanobot/       # Deployment, Service, retained local PV/PVC, private ingress
  cluster/*-sync.yaml         # Staged Flux reconciliation
  scripts/                    # Local image import fallback; upstream CI build is the planned path
  templates/                  # Credential template, never a filled plaintext secret
  .sops.yaml                  # Same public age recipient as Hetzner
```

All application persistence uses static retained local PVs at each app's existing Docker bind-mount source path. Nanobot keeps `/data/nanobot` mounted at `/home/nanobot/.nanobot`. No copying, formatting, replacement storage tree, or recursive ownership change is part of migration. K3s state and container images use the internal system disk at `/var/lib/rancher/k3s`.

Tailscale provides private HTTPS for the nanobot UI. Pi-hole and tailnet DNS changes remain separate work. Flux reads public GitHub over HTTPS; it does not require a GitHub token. The Tailscale operator requires new OAuth credentials encrypted with SOPS before activation.
