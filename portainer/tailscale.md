# Tailscale home-LAN access

This stack runs the official Tailscale container as a **subnet router**. A phone with the Tailscale app can then reach devices and services on the home LAN, including Home Assistant and Pi-hole, without installing Tailscale on every LAN device.

It is intentionally not an exit node: it does not route the phone's general internet traffic through home. Do not set `TS_ROUTES` to `0.0.0.0/0` unless that is explicitly intended.

## Deploy location and prerequisites

Deploy this stack on the Portainer Docker host that is physically connected to the home LAN. The stack will not make a remote/cloud Portainer host into a route to your house.

Before deploying:

1. Identify the home LAN CIDR, for example `192.168.1.0/24`, and the Pi-hole address, for example `192.168.1.2`.
2. Give the Portainer host and Pi-hole stable addresses. A DHCP reservation on the home router is usually preferable to hard-coding static addresses on the devices.
3. Enable forwarding on the underlying Linux host. The settings are host-wide; they cannot be supplied reliably by this Compose file:

   ```sh
   sudo modprobe tun
   printf '%s\n' \
     'net.ipv4.ip_forward = 1' \
     'net.ipv6.conf.all.forwarding = 1' \
     | sudo tee /etc/sysctl.d/99-tailscale-subnet-router.conf
   sudo sysctl --system
   ```

   IPv6 forwarding is included for completeness. If you only advertise IPv4 routes, IPv4 forwarding is the required setting.
4. Confirm that `/dev/net/tun` exists and that the host firewall permits forwarding/masquerading. Tailscale uses SNAT for subnet routes by default, so LAN devices do not need a return route to the Tailscale address range.

## Portainer deployment

Create a Portainer stack from this repository:

- Repository: `https://github.com/breuerfelix/selfhosted.git`
- Compose path: `portainer/tailscale.yaml`
- Branch/ref: the branch you want Portainer to track, normally `main`

Supply these stack environment variables in Portainer. Do not put their values in Git:

| Variable | Example | Purpose |
| --- | --- | --- |
| `TS_AUTHKEY` | `tskey-auth-...` | Tailscale auth key used for the first enrollment |
| `TS_ROUTES` | `192.168.1.0/24` | Home subnet(s) to advertise; comma-separate multiple subnets |
| `TS_HOSTNAME` | `tailscale-subnet-router` | Optional node name |

Create a non-ephemeral auth key in the Tailscale admin console. If device approval is enabled, make it pre-approved or approve the new node after its first start. A short-lived key is appropriate because the state directory is persistent and `TS_AUTH_ONCE=true` prevents reauthentication on normal restarts. If `/data/tailscale` is lost, create a new key and enroll the replacement node.

The stack persists Tailscale identity under `/data/tailscale`, uses kernel networking (`TS_USERSPACE=false`), and uses host networking so it can forward traffic between the Tailscale interface and the home LAN. It needs `/dev/net/tun`, `NET_ADMIN`, and `NET_RAW`; it does not use `privileged: true`.

After the first deployment, check the container logs and node status:

```sh
docker logs tailscale
docker exec tailscale tailscale status --peers=false
docker exec tailscale tailscale ip -4
```

In the Tailscale admin console, open **Machines**, select the new node, and approve the advertised subnet route(s) under **Subnets** unless your tailnet policy auto-approves them. Ensure the tailnet ACL/policy allows the phone's user or group to reach the advertised destination CIDR and required ports. Route advertisement alone is not an access grant.

## Pi-hole as the phone's DNS

1. Ensure Pi-hole listens on its stable LAN address for both UDP and TCP DNS (port 53), and that its firewall/container publishing allows requests from the Portainer host. If Pi-hole is containerized, publish DNS on the host or give it a reachable LAN address.
2. In the Tailscale admin console, open **DNS**.
3. Add the Pi-hole LAN address, such as `192.168.1.2`, as a custom **global nameserver** and enable **Override DNS servers**.
4. Keep Pi-hole's upstream DNS and local DNS records configured as usual. Add a local record for Home Assistant if you want to use a hostname instead of its LAN IP.
5. Install Tailscale on the phone, sign in to the same tailnet, and enable its VPN connection. Leave Tailscale DNS enabled/allowed in the app and the phone OS. Exact labels vary between iOS and Android.

The DNS server is reachable through the advertised LAN route. Using Pi-hole's LAN address is appropriate here; using Pi-hole's Tailscale address instead would require Tailscale to run directly on the Pi-hole host.

Test from the phone while Tailscale is connected:

- Open Pi-hole's admin page at its LAN address, for example `http://192.168.1.2/admin`.
- Open Home Assistant at its LAN address and port, commonly `http://<home-assistant-ip>:8123`, or use the Pi-hole hostname record.
- Open another known home service by its normal LAN address/hostname.
- Confirm that Pi-hole query logging sees the phone's requests.

If a service is only bound to `127.0.0.1` or exists only on an isolated Docker network without a host-published port, a subnet router cannot make it reachable by magic. Bind/publish the service on a LAN-reachable host address, or run Tailscale alongside that service as a separate per-service design.

## Why no static IP or edge appliance is required

Tailscale nodes establish outbound encrypted connections and use NAT traversal. They can connect directly when possible and fall back to an encrypted DERP relay when a direct path cannot be established. A static home public IP and router port-forward are therefore not required. Allowing inbound UDP `41641` can improve the chance of a direct path, but is optional.

There is no dedicated Tailscale hardware edge device requirement. The always-on Docker host running this stack is the edge device. Other valid placements are a small Linux host, NAS, home router with Tailscale support, or another always-on machine on the home LAN.

The existing `cloudflared` tunnel is not a substitute for this subnet router. Cloudflared is an outbound application/tunnel connector for the routes configured in Cloudflare; it is not a Tailscale node and does not provide arbitrary Layer-3 access to the LAN or a DNS path for the phone. It can coexist with this stack on the same home Docker host. If cloudflared is running on a cloud server rather than at home, deploy Tailscale on an actual always-on device at home instead.

Cloudflare does offer a separate **Cloudflare Zero Trust private-network** design: configure private CIDR routes on a tunnel and use the Cloudflare One Client/WARP on the phone. That can be a valid alternative, but it requires Cloudflare device enrollment, routing/split-tunnel policy, and private DNS configuration. It does not make the existing Tailscale app connect through cloudflared, so it is not part of this stack.

## References

- [Tailscale Docker image parameters](https://tailscale.com/docs/features/containers/docker/docker-params)
- [Using Tailscale with Docker](https://tailscale.com/kb/1282/docker/)
- [Subnet routers](https://tailscale.com/kb/1019/subnets/)
- [Configure a subnet router](https://tailscale.com/kb/1406/quick-guide-subnets)
- [DNS in Tailscale](https://tailscale.com/kb/1054/dns/)
- [Block ads with Pi-hole](https://tailscale.com/kb/1114/pi-hole/)
- [Connection types and DERP](https://tailscale.com/kb/1257/connection-types/)
- [Auth keys](https://tailscale.com/kb/1085/auth-keys)
