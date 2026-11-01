# Opt-in LAN ports alongside Tailscale

Implemented 1 November 2026. ServiceLB is enabled through Ansible. Nanobot is reachable at `http://192.168.178.13:8765/` as well as its existing Tailscale HTTPS URL. This document retains the rollout procedure and conventions for future apps.

## Result

Enable K3s's bundled ServiceLB once through Ansible. Each app can then opt in with a small Flux-managed `LoadBalancer` Service, giving `192.168.178.13:<chosen-port>` access to its existing pods. Keep the app's current ClusterIP Service and Tailscale ingress independent.

No extra application replicas, storage changes, reverse proxy, DNS records, certificates, MetalLB, or new chart are required. The initial route serves the app's existing protocol; ServiceLB does not add TLS or authentication.

## Pre-rollout inventory

- Beelink: one Ready node, K3s `v1.36.5+k3s1`, LAN IPv4 `192.168.178.13`, interface `enp1s0`.
- Ansible disables `servicelb`, `traefik`, and `local-storage`. No Kubernetes LoadBalancer Services or pod host ports currently exist.
- Nanobot uses a ClusterIP Service on port 80 targeting its named `http` container port, 8765. Its separate Tailscale ingress works.
- TCP 8765 is currently free after the Docker nanobot migration. Proposed pilot: `http://192.168.178.13:8765`.
- TCP 8888 is occupied by Docker Hindsight. Do not use it for a new app while that container owns it. When Hindsight is migrated later, its old writer/listener must stop before Kubernetes takes that same port.
- Other occupied application ports include 1221, 3001, 3100, 5173, 8000, 8428, 8642, 9119, 9443, and 9999. Repeat inventory immediately before rollout.
- The host has both a globally routed IPv6 address and a ULA; UFW is inactive. Reporting a LAN address in a Service's status does not itself restrict access.

## 1. Enable the bundled controller

In `beelink/ansible/k3s.yml`, remove only `servicelb` from the generated `disable` list. Keep Traefik and dynamic local storage disabled. No K3s reinstall or version change is needed.

Run Ansible syntax validation and review a `--check --diff` preview, then apply the playbook. Its existing configuration handler restarts K3s when the config changes. Expect a short control-plane interruption; verify node, CoreDNS, Flux, Tailscale, and application readiness afterward. Docker apps do not need to stop for this controller change.

ServiceLB is built into K3s. It creates a small managed DaemonSet for each opted-in Service, reserving the selected host port. Enabling the controller alone does not expose existing ClusterIP Services. [K3s ServiceLB](https://docs.k3s.io/networking/networking-services#service-load-balancer).

## 2. Add one LAN Service per opted-in app

Use a separate `lan.yaml` inside the app directory and list it in that app's `kustomization.yaml`. Nanobot's active Service is `beelink/cluster/apps/nanobot/lan.yaml`. `beelink/templates/nanobot-lan.yaml.example` is an inactive reference pattern for other apps; change its names, selector, and port before use.

Conventions:

- Name: `<app>-lan`; same namespace and selector as the app.
- Type: `LoadBalancer`, with `loadBalancerClass` omitted so K3s's default implementation handles it.
- No `tailscale.com/expose` annotation or Tailscale load-balancer class on this LAN Service. The existing Tailscale Ingress continues using the original ClusterIP Service.
- `port` is the host/LAN port; `targetPort` identifies the app's existing container port. They may differ. Declare TCP or UDP explicitly; publish only required ports.
- `externalTrafficPolicy: Cluster` and `allocateLoadBalancerNodePorts: false`. This uses ServiceLB's ClusterIP forwarding path without allocating additional high host ports. Do not change this combination to `Local` without revisiting the design: this K3s release's Local path forwards through NodePorts. [Pinned controller implementation](https://github.com/k3s-io/k3s/blob/v1.36.5%2Bk3s1/pkg/cloudprovider/servicelb.go), [Kubernetes NodePort allocation](https://kubernetes.io/docs/concepts/services-networking/service/#disabling-load-balancer-nodeport-allocation).
- Start IPv4-only with `ipFamilyPolicy: SingleStack` and `ipFamilies: [IPv4]`.
- Set `loadBalancerSourceRanges: [192.168.178.0/24]` for external LAN clients. This version passes the ranges to the ServiceLB proxy's source filters. Verify actual generated rules and reachable addresses during rollout; this is a source restriction, not a host-IP bind setting. [Pinned proxy implementation](https://github.com/k3s-io/klipper-lb/blob/v0.4.17/entry).

Keep a stable DHCP reservation for `192.168.178.13`. No router port forwarding is needed. No router/browser settings are changed by this plan; provide the user steps if a router check becomes necessary.

## 3. Port ownership and preflight

Before every new LAN Service, check host sockets, Docker published ports, existing Kubernetes Services, and all pod `hostPort` declarations. Reserve each `(protocol, port)` once per node; TCP and UDP are separate reservations. Kubernetes scheduling does not provide a reliable inventory of Docker's published sockets, so do not rely on a Pending ServiceLB pod to detect every conflict.

Port mapping:

| App | LAN port | Backend | Existing Tailscale route |
|---|---|---|---|
| nanobot | TCP 8765 | named container port `http` (8765) | `https://nanobot.vulture-skink.ts.net/` |
| future Hindsight migration | TCP 8888, once Docker releases it | confirm when migrating | add separately if wanted |

The nanobot LAN change adds a Service only. It does not alter the Deployment, image, replicas, PV/PVC, original Service, or ingress. A separately merged nanobot image update was preserved during rollout.

## 4. Deploy and verify

1. Recheck ports and capture current application/Docker health.
2. Apply the Ansible controller change and confirm K3s recovery.
3. For another app, copy the reference template to its `lan.yaml`, choose a free port and correct selector, add it to the app's Kustomize resources, render, and run a server-side dry-run. Nanobot's file is already active.
4. Commit/push the reviewed files and reconcile Flux. Do not manually maintain generated ServiceLB DaemonSets.
5. Confirm `nanobot-lan` gets `192.168.178.13`, its generated `svclb-*` pod becomes Ready, and no NodePort was allocated.
6. From the Mac's LAN connection, test `http://192.168.178.13:8765/` and the app's login behavior. Check that any browser features needed by the app also work over plain HTTP.
7. Verify the existing Tailscale HTTPS URL and certificate still work, and the application data mount and unrelated Docker apps are healthy.
8. Inspect ServiceLB/kube-proxy/CNI rules for the LAN source restriction and IPv4-only exposure. Check that the new port is not accidentally reachable through global IPv6. An approved LAN address in status is not proof of isolation; report any validation limits if an external negative test is unavailable.

`ss` alone is insufficient for post-deployment validation: forwarding can be implemented with network rules instead of a userspace listener. Use live connection tests and inspect generated resources/rules.

## 5. Rollback

Remove only the app's `lan.yaml` resource through Git and reconcile Flux. Verify the generated ServiceLB pod/DaemonSet disappears and the LAN port is released. The existing ClusterIP Service, Tailscale ingress, app pod, and data remain in place.

If the controller itself must be reverted and no other app depends on it, restore `servicelb` to Ansible's disabled list and rerun the playbook. This requires another K3s restart. There is no data migration or Docker restart in this rollback.

## Acceptance

- A selected app is reachable over the chosen LAN IP/port and its existing Tailscale HTTPS URL.
- Apps without a LAN Service gain no new LAN endpoint.
- Port conflicts are avoided, no extra NodePorts are allocated, and IPv4/source filtering is verified.
- All resources are managed by Ansible or Flux. No Pi-hole DNS record or certificate setup is required.

## Verified rollout results

- Ansible preview changed only the ServiceLB disable flag; apply restarted K3s and the node recovered Ready. A second run reported `changed=0`, `failed=0`.
- `nanobot-lan` is a Ready IPv4 LoadBalancer at `192.168.178.13`, TCP port 8765. It has no allocated NodePort. Its generated ServiceLB DaemonSet has one Ready pod.
- HTTP returned 200 from the Mac, explicitly bound to LAN source `192.168.178.48` on `en0`. Existing Tailscale HTTPS returned 200 with certificate verification enabled.
- ServiceLB and kube-proxy rules contain the LAN source allow and other-source drop rules. There are no corresponding IPv6 forwarding rules. A connection to Beelink's global IPv6 address on port 8765 was refused, while the same IPv6 address accepted a control connection on SSH port 22. This tests exposure from the local network, not a separate off-site internet client.
- Nanobot's retained PVC remains Bound. Existing Docker container IDs and start timestamps remained unchanged.
- No DNS, certificate, router, or browser changes were required.
