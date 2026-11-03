# Tailscale and home DNS

Flux manages the operator under `cluster/infrastructure/tailscale`. The encrypted `operator-oauth.sops.yaml` Secret supplies `client_id` and `client_secret`; credentials are not Helm values. Its tailnet hostname is `beelink-k8s-operator`.

## Tailnet prerequisites

Merge these entries into the existing `tagOwners` object under [Access controls](https://console.tailscale.com/admin/acls/file), preserving other policy sections:

```json
"tag:k8s-operator": [],
"tag:k8s": ["tag:k8s-operator"]
```

Enable MagicDNS and HTTPS Certificates in the tailnet DNS settings. Allow intended clients to reach `tag:k8s` on TCP 443. Keep Funnel disabled for these private apps. Each Tailscale Ingress creates an HTTPS proxy for its declared hostname; no public reverse proxy or router port forwarding is required.

Public HTTPS certificates expose their hostnames in Certificate Transparency logs even though access remains private. Avoid sensitive service names. See [Tailscale HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates).

## Pi-hole and client DNS

Pi-hole runs separately on the Raspberry Pi, outside Kubernetes and this repository's Ansible configuration:

| Endpoint | Address | Purpose |
| --- | --- | --- |
| Pi-hole LAN | `192.168.178.12` | DNS for home devices |
| Pi-hole Tailscale | `100.107.42.49`, `pihole.vulture-skink.ts.net` | DNS for connected tailnet clients |

Use `100.107.42.49` as the tailnet's global nameserver with **Override DNS servers** enabled. Mac and phone clients must accept Tailscale DNS. Keep MagicDNS enabled for application names. The LAN address is for local DNS; remote clients reach the Pi through its Tailscale address.

The Pi must not accept the DNS policy pointing back to itself; keep its Tailscale DNS acceptance disabled (`--accept-dns=false`). Pi-hole must accept trusted DNS requests through both LAN and Tailscale interfaces on UDP and TCP 53. If restoring Pi-hole, follow the [official Pi-hole setup](https://tailscale.com/docs/solutions/block-ads-all-devices-anywhere-using-raspberry-pi) for interface settings. Do not expose port 53 publicly; restrict tailnet DNS access to intended clients.

No home subnet route or exit node is needed for DNS or application ingress. This avoids routing conflicts on other `192.168.178.0/24` networks. Clients use the same Tailscale application URLs at home and away. Direct peer connections are preferred when available; relayed connections still work.

Kubernetes Service DNS remains handled by CoreDNS. Pi-hole does not replace cluster DNS. Hetzner's public HTTPS ingress is documented separately in [its overview](../../hetzner/docs/README.md).

## DNS checks and recovery

Run these checks on the Mac with Tailscale connected:

```sh
tailscale dns status
tailscale ping --c=1 pihole
dig @100.107.42.49 example.org A
dig +tcp @100.107.42.49 example.org A
dig @192.168.178.12 example.org A
dscacheutil -q host -a name grafana.vulture-skink.ts.net
```

The LAN query requires home-LAN connectivity. Direct `dig` queries test DNS reachability; check Pi-hole's query log to verify client filtering. Use `tailscale dns status` and the native macOS lookup to check the client's actual resolver configuration.

If the Pi or home internet is unavailable, ordinary DNS resolution can fail for clients using the override. Temporarily disable **Override DNS servers** in the Tailscale admin console, or turn off **Use Tailscale DNS** on the affected client. Re-enable it after repair. Local system DNS then applies, and filtering may be bypassed. Do not add a public secondary resolver as presumed ordered failover: resolver selection can bypass Pi-hole. See [Tailscale DNS behavior](https://tailscale.com/docs/reference/dns-in-tailscale#the-order-of-dns-resolvers).

## OAuth credentials

Create an OAuth client under [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials) with write scopes **General / Services**, **Devices / Core**, and **Keys / Auth Keys**, associated with `tag:k8s-operator`. Use the [official operator setup](https://tailscale.com/docs/kubernetes-operator/install-operator) to check available scopes. Store the client secret securely when shown.

Edit the existing encrypted Secret from the repository root:

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml
```

Update `stringData.client_id` and `stringData.client_secret` in the SOPS editor. Saving encrypts both values; keep plaintext credentials out of Git and chat. Push the reviewed encrypted change, then reconcile and restart the operator:

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
flux reconcile kustomization tailscale --with-source --timeout=10m
kubectl -n tailscale rollout restart deployment/operator
kubectl -n tailscale rollout status deployment/operator --timeout=300s
flux reconcile helmrelease tailscale-operator -n tailscale --timeout=10m
```

The operator requires this Secret to start. Unlimited Helm install remediation allows recovery after credentials become available. Confirm enrollment in the tailnet Machines list with `tag:k8s-operator`, approve the device if policy requires it, and verify an app's HTTPS route with certificate validation.
