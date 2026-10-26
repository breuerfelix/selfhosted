# Hetzner Cloud Firewall checkpoint

Cloud Firewall is configured in Hetzner Console or through Hetzner API, not through `ssh cool`. User reported it attached on 2026-10-26. A fresh SSH connection succeeded after attachment, then K3s started and direct Mac API access succeeded. Provider firewall rule contents cannot be read through SSH.

User reported TCP 22 and TCP 6443 are currently allowed from anywhere and will be tightened later. The table below is the original recommended rule set, **not a verified snapshot** of current Hetzner Console rules.

Proposed incoming rules for VPS `cool`:

| Protocol and port | Source | Purpose |
| --- | --- | --- |
| TCP 22 | `0.0.0.0/0`, `::/0` | Preserve SSH access during setup. Narrow only in a later step after testing. |
| TCP 80, 443 | `0.0.0.0/0`, `::/0` | Public web ingress, deployed later. |
| TCP 6443 | Current Mac public IPv4 `/32` | Recommended later tightening for direct Kubernetes API access from Mac. Current SSH source on 2026-10-26 was `89.1.213.170/32`; verify it has not changed. |

Leave outgoing rules empty so outgoing traffic remains allowed. Hetzner Cloud Firewall drops all other new inbound traffic by default and preserves established connections. These rules block public access to K3s kubelet and Flannel ports without host UFW/nftables rules. See https://docs.hetzner.com/cloud/firewalls/faq/.

Safe order:

1. Create firewall and inspect all incoming rules before attaching it to server. Confirm TCP 22 is allowed from both IPv4 and IPv6 Internet.
2. Attach firewall to VPS. Keep current SSH session open.
3. Open a separate fresh terminal/session and run `ssh cool 'hostname; uptime -p'`. Only fresh connection verifies new inbound SSH works.
4. If fresh SSH fails, detach firewall in Hetzner Console. Existing session may remain established, but do not rely on it for recovery.
5. Report successful attachment and fresh SSH test before running `hetzner/ansible/k3s-start.yml`. This was done on 2026-10-26.

An IP-limited API rule requires updating when Mac's public IP changes. The kubeconfig on Mac will contain cluster-admin credentials; keep it mode `0600` in ignored `temp/` and never commit it.
