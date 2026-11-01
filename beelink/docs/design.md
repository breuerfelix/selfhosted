# Reviewed Beelink design

Reviewed 31 October 2026 against the live host, the Hetzner manifests, and upstream documentation. The original [homelab proposal](../../homelab-k3s-tailscale-pihole-design.md) is background; the findings below supersede its implementation order for this host.

The inventory below records pre-bootstrap state. K3s was subsequently installed through Ansible and nanobot migrated through Flux; see [current status](status.md). GitHub Actions now builds the upstream image; no Docker image import is needed.

## Verified host state

| Item | Observed value |
|---|---|
| Access / hostname | `ssh bee` as root / `beelink` |
| OS / architecture | Ubuntu 24.04.5 / amd64 |
| Current LAN address | `192.168.178.13` on `enp1s0`, assigned by DHCP |
| Memory | 15 GiB, approximately 10 GiB available during inventory |
| K3s | Not installed |
| Docker | Portainer and existing applications running |
| System disk | `/dev/sda2`, approximately 305 GiB free |
| Data disk | `/dev/nvme0n1`, ext4, mounted at `/data`, approximately 1.6 TiB free |
| Data filesystem UUID | `3da917f6-a469-43f4-831a-5a9eef982cd5`, already in `/etc/fstab` |
| Host firewall | UFW inactive; no firewall changes included in this phase |
| Existing Tailscale | Host-network Docker container; advertises `192.168.178.0/24`, accepts neither routes nor tailnet DNS, no exit node selected |

The user's SSD description maps to the existing `/data` filesystem. Linux reports NVMe transport; exact enclosure type does not affect the design. The filesystem UUID and mount path are the storage identities to preserve.

## Findings on the original proposal

1. **Private application ingress is feasible.** The Tailscale operator supports an HTTPS Ingress backed by a ClusterIP Service and creates its own proxy. A new host-level Tailscale daemon, Traefik, cert-manager, public port forwards, and a shared ProxyGroup are unnecessary here. MagicDNS and tailnet HTTPS must be enabled. Certificate hostnames enter public Certificate Transparency logs. [Operator ingress](https://tailscale.com/docs/kubernetes-operator/ingress).
2. **Pi-hole is independent.** Nanobot does not require a Pi-hole migration or global DNS override. Defer Raspberry Pi changes, client DNS changes, and subnet-route removal. The current Docker Tailscale router can coexist with the operator. Its advertised home subnet remains an overlap risk for clients accepting that route; operator ingress does not depend on it.
3. **Flux and SOPS are initial requirements.** Use a separate Flux installation with `path: ./beelink/cluster`, reading the same public repository and branch as Hetzner. Every child Kustomization that can consume secrets references `flux-system/sops-age`. Install the same private age identity in this cluster; only its public recipient is committed. [Flux SOPS](https://fluxcd.io/flux/guides/mozilla-sops/).
4. **Bind-mount reuse works with static local PVs.** Keep each existing source path, node affinity to `beelink`, an explicit PV/PVC binding, empty storage class, and `Retain`. Disable K3s's dynamic local-storage provisioner so future PVCs cannot silently create a new layout on the system disk. `20Gi` on nanobot's PV/PVC is binding metadata, not a quota. [Local volumes](https://kubernetes.io/docs/concepts/storage/volumes/#local).
5. **Storage needs a startup check.** A directory existing under `/data` does not prove the SSD is mounted. Ansible verifies the UUID and existing config before installation. The K3s systemd unit requires `data.mount` and checks its UUID before starting. This prevents booting against an empty directory on the system disk. It is not hot-unplug protection or a backup mechanism.
6. **Stopping only nanobot is insufficient.** Both `nanobot` and `nanobot-api` mount `/data/nanobot` read-write. Stop both and disable their Docker restart policies before Kubernetes starts. `ReadWriteOnce` does not lock out Docker, and it allows multiple pods on one node. Use one replica with `Recreate`; prevent Portainer from redeploying the old stack.
7. **Build upstream sources through CI.** GitHub Actions builds the pinned commit in `images/nanobot/source.json` with the upstream Dockerfile, tests the gateway/WebUI as UID 1000 using disposable state, publishes to public GHCR, and opens a digest-update PR. Flux deploys the merged digest. The first build and live cutover passed. No registry credentials, forked Dockerfile, source copy, or manual image import are needed. Python dependencies and base-image tags are resolved at build time; the Deployment digest pins the resulting artifact. [Image build](../images/nanobot/README.md).

## Chosen cluster setup

- One K3s server, SQLite, bundled containerd, Flannel and CoreDNS. Docker remains independent for the apps not being migrated.
- Ansible installs an explicit initial K3s version and preserves an existing version on reruns. No automatic K3s upgrade controller in this first phase; maintenance upgrades need a separately reviewed version change and procedure. The bootstrap version matches the current Hetzner configuration.
- Disable bundled Traefik and local-storage. ServiceLB is enabled for opt-in LAN Services; nanobot publishes IPv4 TCP 8765, restricted to LAN sources. See [the LAN Service pattern](servicelb-plan.md). Retain the default pod/service networks (`10.42.0.0/16`, `10.43.0.0/16`), which do not overlap the observed LAN or Docker routes.
- Pin the node IP and Flannel interface to the host's current default LAN interface, avoiding selection of the existing Tailscale interface. Keep the current DHCP lease stable with a router reservation; the playbook does not change router settings.
- Keep the host's existing swap enabled and explicitly set kubelet `fail-swap-on=false`; this does not enable workload swap. No host DNS rewrite. CoreDNS uses K3s's normal resolver selection.
- Kubernetes API administration uses the LAN or an SSH tunnel through `bee`. The API is authenticated by its kubeconfig. Do not add router forwards. No Kubernetes API proxy through Tailscale in this phase.
- Flux source, Kustomize, and Helm controllers only. Generated components are kept under `beelink/`, independently of Hetzner.
- Root Flux sync enables Tailscale and nanobot. Nanobot depends on Tailscale readiness. Keep it suspended during a first migration or restore until all other writers are stopped and data is ready. Change suspension flags in Git; root reconciliation would overwrite a CLI-only resume.

## Nanobot mapping

| Setting | Existing Docker | Kubernetes |
|---|---|---|
| Image | `selfhosted-nanobot:0.4.0` | GitHub Actions build from pinned upstream sources, GHCR digest in `app.yaml` |
| Source | Upstream `v0.4.0` | Same upstream commit; current pin in `images/nanobot/source.json` |
| Entrypoint / argument | `entrypoint.sh gateway` | Image entrypoint retained; `args: [gateway]` |
| Process user | Entrypoint drops root to UID:GID `1000:1000` | Start directly as `1000:1000`, matching existing SSD ownership |
| Persistent mount | `/data/nanobot:/home/nanobot/.nanobot` | Identical host and container paths through a retained local PV |
| Environment | `NANOBOT_DOCKER_BOOTSTRAP=1`, `XDG_DATA_HOME=/home/nanobot/.nanobot/data` | Same settings |
| UI / WebSocket | HTTP on `0.0.0.0:8765`; `/` returned HTML 200 | ClusterIP port 80 targets 8765; Tailscale HTTPS ingress hostname `nanobot` |
| Gateway health | HTTP `127.0.0.1:18790/health` inside the container | Exec startup/liveness probes; port not exposed in a Service |
| API | Separate `serve` process, port 8900, same mount | No deployment, Service, or ingress |

Keep the existing mutable `/data/nanobot/config.json` on the SSD. Its provider credentials, sessions, workspace, databases, caches, and installed tools stay in place. Do not overlay a read-only Kubernetes Secret onto that file: it would change the app's current config editing behavior. SOPS protects new Git-managed secrets such as operator OAuth; it does not encrypt existing files on the SSD. If config later becomes Git-managed, make that an explicit separate change.

No Docker-only service names or custom provider endpoints were found in the inspected config. Gateway health and the private HTTPS UI passed after cutover. A real provider/tool request and interactive login/chat remain user checks; HTTP 200 does not prove those paths. The actual Ingress address is `nanobot.vulture-skink.ts.net`. Check hostname availability before reproducing this setup in another tailnet.

## Tailscale prerequisites

Use the stable Helm chart pinned in `release.yaml`. Leave its OAuth values empty; the chart mounts a separately managed `tailscale/operator-oauth` Secret containing `client_id` and `client_secret`.

The tailnet admin must merge tag ownership entries into the existing policy, create an OAuth client with write scopes `General/Services`, `Devices/Core`, and `Keys/Auth Keys` associated with `tag:k8s-operator`, and enable MagicDNS/HTTPS. The existing Docker auth key is not an operator OAuth client. Operator identity: `beelink-k8s-operator`; app proxy tag: `tag:k8s`. [Current operator installation guide](https://tailscale.com/docs/kubernetes-operator/install-operator).

Allow intended users/devices to reach `tag:k8s` on TCP 443 under the existing access policy. Tailnet membership alone does not grant access when that policy denies it. Review nanobot's own authentication; its agent can execute tools. Keep Funnel disabled. No Pi-hole credential, new DNS server, exit node, or advertised route is required.

## Recovery and later apps

Both PV and PVC opt out of Flux pruning, and the PV has `Retain`. This preserves object/data identity during ordinary manifest removal; deleting a namespace still deletes its namespaced PVC. A retained PV can become `Released` after claim deletion and needs deliberate rebinding. Never delete SSD files to fix a claim.

Before rolling back, suspend nanobot reconciliation and scale its deployment to zero; verify all nanobot pods have stopped before starting Docker against the same mount. Keep the old API stopped unless it is specifically needed again. The first migration uses identical app code, minimizing schema drift; later upgrades might require restoring a pre-upgrade backup.

The existing Restic container is outside this migration. The repository's Restic job lists only Portainer, Hermes backups, and Hindsight; it does not include `/data/nanobot`. The user has existing backups through another procedure. Verify that procedure remains consistent after cutover: scripts that stop Docker containers will no longer quiesce the Kubernetes writer. K3s SQLite/token and operator state are separate recovery items; rebuilding from Git plus SSD data requires reinstalling the age key and OAuth credentials and may recreate tailnet device identities.

For every later app, first inspect its live Docker mounts, users, command, environment, ports, and dependencies. Preserve every required mount at its current SSD path, including multiple paths when present. Do not add obsolete apps to Flux. No Longhorn, NFS, distributed storage, shared proxy fleet, or monitoring migration is included.
