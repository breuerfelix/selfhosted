# Public ingress and TLS

Activated 2026-10-26 through Flux. K3s-packaged Traefik and ServiceLB serve VPS ports 80/443. No custom Traefik `HelmChartConfig` is installed. cert-manager's production `ClusterIssuer/letsencrypt-prod` uses Let's Encrypt HTTP-01, `ingressClassName: traefik`, and contact `felix@breuer.dev`. DNS A records for all four hosts resolved to `91.99.161.123`; no AAAA records were returned at activation. The Hetzner firewall allows web ports.

| Host | Git definition | Result | TLS Secret |
| --- | --- | --- | --- |
| `danielkueffler.de` | `apps/ghost/ingress.yaml` | Ghost homepage | `apps/ghost-tls` |
| `stats.felixbreuer.me` | `apps/fathom/ingress.yaml` | Fathom | `apps/fathom-tls` |
| `photos.felixbreuer.me` | `apps/noobgallery/ingress.yaml` | Noobgallery | `apps/noobgallery-tls` |
| `felixbreuer.me` | `apps/redirect/native-redirect.yaml` | Permanent redirect to `https://breuer.dev/`, retaining path and query | `apps/felixbreuer-me-tls` |

The first three apps use Kubernetes Ingress objects on `websecure` with cert-manager annotations and separate HTTP Ingress objects with Traefik's shared `apps/redirect-https` Middleware. cert-manager's HTTP-01 solver Ingress takes precedence for challenges on port 80. `felixbreuer.me` uses a Traefik `RedirectRegex` Middleware and HTTP/HTTPS `IngressRoute` objects backed by `noop@internal`; it needs no redirect container. Its Certificate is explicit because cert-manager's ingress-shim watches Kubernetes Ingress objects, not Traefik IngressRoutes. The obsolete `grahamdigital/simple-redirect` pod and Service were removed after the native route and new certificate were ready. The old `redirect-tls` Secret was deleted after its Ingress and Certificate disappeared.

## Verify

```bash
KUBECONFIG=temp/hetzner-kubeconfig kubectl get clusterissuer letsencrypt-prod
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get certificates,ingresses,ingressroutes,middlewares
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get deploy,pvc
curl -I http://danielkueffler.de/
curl -I https://danielkueffler.de/
curl -I https://stats.felixbreuer.me/
curl -I https://photos.felixbreuer.me/
curl -I 'https://felixbreuer.me/path?x=1'
```

Expected: ClusterIssuer and four Certificates Ready; Ghost/Fathom/Noobgallery Deployments 1/1; Ghost/Fathom PVCs Bound; first three HTTPS routes return 200; HTTP app routes redirect to HTTPS; final redirect returns `Location: https://breuer.dev/path?x=1`. The HTTPS requests validate Let's Encrypt certificates without `curl -k`. Unknown hosts still return Traefik 404. Screeps has no public route yet.

If issuance fails, inspect `Certificate`, `CertificateRequest`, `Order`, and `Challenge` in `apps`; check DNS A/AAAA and public port 80. Do not apply certificates or private keys manually. Flux owns route manifests; cert-manager owns generated Secrets and renewals. A fresh-cluster restore recreates certificates from Git definitions and ACME, subject to DNS and rate limits. See [cert-manager.md](cert-manager.md).
