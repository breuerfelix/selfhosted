# Automatic K3s patch updates

Installed 2026-10-26. Flux manages Rancher system-upgrade-controller `v0.20.2` and one `Plan/k3s-server`. The controller Deployment uses `rancher/system-upgrade-controller:v0.20.2` pinned to image digest `sha256:61b68d4372baf7ae90fb0f879feea1c082381a8b7547cc5ec85d393c497b11cb`. Its kubectl helper is `rancher/kubectl:v1.36.2` pinned to digest `sha256:06c7a7a9772737494ae1e0c3af90f1b5385630c147e47c1c7cea92f4bed55fbe`. The upstream release's CRD and controller manifests are vendored under `hetzner/cluster/infrastructure/system-upgrade-controller/`; original release asset SHA-256 values are `1fb061e0d8bf9534da0145e614a9e03ca376cd5d1adcca17d13cfa12e211c48c` and `fd474b662d1f2b74ab150d95b6482869e1fd1f27ceee54b13e94b92292097969`. Only those two image references were changed in the controller manifest. Renovate scans its Deployment image; review controller, CRD, and helper updates together.

The Plan in `hetzner/cluster/infrastructure/k3s-upgrade-plan/server-plan.yaml` tracks `https://update.k3s.io/v1-release/channels/v1.36`: only K3s `v1.36` patch releases. `rancher/k3s-upgrade` has no fixed tag because the controller uses the channel-resolved K3s version as its tag. The single control-plane node is targeted with concurrency 1. There is no drain or cordon: this node has no alternative placement, and K3s restart already interrupts the cluster briefly.

Upgrade Jobs may **start daily between 04:00 and 05:00 Europe/Berlin**. A Job already started may run after 05:00. Ubuntu package refresh is at 01:00, unattended updates at 02:00, and conditional reboot at 03:00. The one-hour gap reduces overlap but cannot guarantee it if host update or reboot runs unusually long. K3s may restart during an upgrade; controlled reboot recovery of all apps passed before enabling this Plan.

Flux's root Kustomization installs the CRD/controller and creates a second Flux Kustomization, `flux-system/k3s-upgrade-plan`. That child waits for root readiness before applying the Plan, so a fresh bootstrap has the CRD before its custom resource. At activation, controller was Ready; Plan was Validated, resolved `v1.36.5-k3s1` (same as installed), and reported `Complete=False` with `current time is not within configured window`. No upgrade Job existed. The first window may create a baseline Job even if the installed version already matches; check the Plan and node after 04:00. No scheduled upgrade has been tested yet.

## Verify after a window

```bash
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n system-upgrade get deploy,plan,jobs,pods
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n system-upgrade describe plan k3s-server
KUBECONFIG=temp/hetzner-kubeconfig kubectl get nodes -o wide
KUBECONFIG=temp/hetzner-kubeconfig flux get kustomizations -A
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get deploy,pvc,certificates
ssh cool 'k3s --version; systemctl is-active k3s'
```

Check public routes after a successful upgrade. Controller Jobs have a 15-minute active deadline and are removed 15 minutes after completion by its default config; Plan status, node version, and events remain useful afterward. A failed Plan requires investigation; do not blindly change version or force another Job.

## Moving to a new Kubernetes minor

Minor version changes such as `v1.36` to `v1.37` are **reviewed Git changes**, not automatic channel movement. Review K3s/Kubernetes release notes and compatibility of Flux, cert-manager, bundled Traefik, and app manifests. Move one minor at a time. Update the Plan channel, matching kubectl helper image, and `k3s_bootstrap_version` in `hetzner/ansible/k3s.yml` for fresh-host installs. The Ansible playbook skips installation when K3s already exists, so it will not downgrade a live node. Commit changes before the chosen 04:00 window, observe the Job, then verify cluster and public routes. Larger version migrations also require a separate review. The user deferred ongoing backups until a later AWS S3 design; the existing Mac migration archive is not a current automated backup.

Sources: https://docs.k3s.io/upgrades/automated and https://github.com/rancher/system-upgrade-controller/blob/master/doc/plan.md
