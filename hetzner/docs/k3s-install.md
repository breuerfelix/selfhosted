# K3s bootstrap checkpoint

Host storage is copied and verified; Docker/Coolify containers remain stopped. `hetzner/ansible/k3s.yml` staged K3s **without starting or enabling it** on 2026-10-26. After user reported Hetzner Cloud Firewall attached and fresh SSH succeeded, `hetzner/ansible/k3s-start.yml` enabled and started K3s. Node and all bundled deployments became Ready; second run of each playbook reported `changed=0`.

Bootstrap version: `v1.36.5+k3s1`, stable channel result checked 2026-10-26. Ansible installer task runs only when `/usr/local/bin/k3s` is absent. Later Flux system-upgrade-controller will own automatic patch upgrades on the `v1.36` channel. Re-running Ansible must not reinstall an older binary.

K3s config lives at `/etc/rancher/k3s/config.yaml`, managed by Ansible. It disables bundled Traefik so ingress can be pinned and managed by Flux later, adds server public IPv4 as TLS SAN for Mac kubeconfig, and keeps root-only kubeconfig permissions. All other core choices stay at K3s defaults: one server, SQLite, bundled containerd, CoreDNS, ServiceLB, and local-path provisioner. No application manifests, PVs, or Flux controllers are installed in this stage.

## Stage inactive K3s

```bash
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s.yml --check --diff
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s.yml
ssh cool 'systemctl is-active k3s; systemctl is-enabled k3s; ss -lnt | grep :6443 || true'
```

Expected: binary and service files exist; service is not active or enabled; no listener on 6443. The installer task is guarded by absence of `/usr/local/bin/k3s` and will not downgrade a later system-upgrade-controller version.

## Activate only after firewall checkpoint

First verify a **new** `ssh cool` connection after firewall attachment; see [firewall.md](firewall.md). Then:

```bash
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini hetzner/ansible/k3s-start.yml -e firewall_verified=true
ssh cool 'systemctl is-enabled k3s; systemctl is-active k3s; k3s kubectl get nodes; k3s kubectl -n kube-system get pods'
```

The second playbook refuses to start without `firewall_verified=true`. After activation, copy `/etc/rancher/k3s/k3s.yaml` to an ignored, mode-0600 file on Mac and change server URL from `https://127.0.0.1:6443` to VPS public IPv4. Verify `kubectl get nodes` directly from Mac. Do not commit kubeconfig.

Node, system pods, service enablement, and Mac API access were checked on 2026-10-26. Flux, Ghost/Fathom PVs, and four internal app workloads were deployed afterward; see [flux-bootstrap.md](flux-bootstrap.md) and [migration-runbook.md](migration-runbook.md). A real reboot recovery test and automatic K3s updates remain later stages.
