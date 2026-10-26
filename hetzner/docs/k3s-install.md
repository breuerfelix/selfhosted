# K3s bootstrap checkpoint

Host storage is copied and verified; Docker/Coolify containers remain stopped. `hetzner/ansible/k3s.yml` originally staged K3s **without starting or enabling it** on 2026-10-26. After user reported Hetzner Cloud Firewall attached and fresh SSH succeeded, `hetzner/ansible/k3s-start.yml` enabled and started K3s. Node and core deployments became Ready.

Bootstrap version: `v1.36.5+k3s1`, stable channel result checked 2026-10-26. Ansible installer task runs only when `/usr/local/bin/k3s` is absent. Later Flux system-upgrade-controller will own automatic patch upgrades on the `v1.36` channel. Re-running Ansible must not reinstall an older binary.

K3s config lives at `/etc/rancher/k3s/config.yaml`, managed by Ansible. Current desired config leaves bundled Traefik enabled, adds server public IPv4 as TLS SAN for Mac kubeconfig, and keeps root-only kubeconfig permissions. Other core choices stay at K3s defaults: one server, SQLite, bundled containerd, CoreDNS, ServiceLB, and local-path provisioner. K3s selects the packaged Traefik chart with its own release. No separate Flux HelmRelease or `HelmChartConfig` is needed for default behavior. Ansible restarts an already-running K3s service only if this config changes; it does not rerun the pinned bootstrap installer.

## Initial staging (completed)

```bash
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s.yml --check --diff
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s.yml
ssh cool 'systemctl is-active k3s; systemctl is-enabled k3s; ss -lnt | grep :6443 || true'
```

At initial install: binary and service files exist; service is not active or enabled; no listener on 6443. The installer task is guarded by absence of `/usr/local/bin/k3s` and will not downgrade a later system-upgrade-controller version. On an active host, the same playbook applies K3s config and restarts K3s only if it changed.

## Initial activation after firewall checkpoint (completed)

First verify a **new** `ssh cool` connection after firewall attachment; see [firewall.md](firewall.md). Then:

```bash
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s-start.yml -e firewall_verified=true
ssh cool 'systemctl is-enabled k3s; systemctl is-active k3s; k3s kubectl get nodes; k3s kubectl -n kube-system get pods'
```

The second playbook refuses to start without `firewall_verified=true`. After activation, copy `/etc/rancher/k3s/k3s.yaml` to an ignored, mode-0600 file on Mac and change server URL from `https://127.0.0.1:6443` to VPS public IPv4. Verify `kubectl get nodes` directly from Mac. Do not commit kubeconfig.

Node, system pods, service enablement, and Mac API access were checked on 2026-10-26. Flux, Ghost/Fathom PVs, and application workloads were deployed afterward; see [flux-bootstrap.md](flux-bootstrap.md) and [migration-runbook.md](migration-runbook.md). Bundled Traefik was enabled later by removing `disable: traefik` from Ansible's config and rerunning `k3s.yml`. Verify its HelmChart, Deployment, LoadBalancer Service, and ServiceLB pods. ServiceLB uses host ports and NAT, so `ss` need not show conventional port 80/443 listeners; verify access with HTTP requests instead. Public app routes and TLS were added after Traefik activation; see [ingress.md](ingress.md). A real reboot recovery test and automatic K3s updates remain later stages.
