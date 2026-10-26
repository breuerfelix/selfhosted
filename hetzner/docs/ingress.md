# Public ingress and TLS

Activated 2026-10-26 through Flux. K3s-packaged Traefik and ServiceLB serve VPS ports 80/443. Git-managed `kube-system/HelmChartConfig/traefik` configures a global `web` to `websecure` redirect; K3s still supplies the compatible Traefik chart and image. cert-manager's production `ClusterIssuer/letsencrypt-prod` uses Let's Encrypt HTTP-01, `ingressClassName: traefik`, and contact `felix@breuer.dev`. DNS A records for all five hosts resolved to `91.99.161.123`; no AAAA records were returned at activation. The Hetzner firewall allows web ports.

| Host | Git definition | Result | TLS Secret |
| --- | --- | --- | --- |
| `danielkueffler.de` | `apps/ghost/ingress.yaml` | Ghost homepage | `apps/ghost-tls` |
| `stats.felixbreuer.me` | `apps/fathom/ingress.yaml` | Fathom | `apps/fathom-tls` |
| `photos.felixbreuer.me` | `apps/noobgallery/ingress.yaml` | Noobgallery | `apps/noobgallery-tls` |
| `screeps.felixbreuer.me` | `apps/screeps/ingress.yaml` | Screeps web UI and API | `apps/screeps-tls` |
| `felixbreuer.me` | `apps/redirect/native-redirect.yaml` | Permanent redirect to `https://breuer.dev/`, retaining path and query | `apps/felixbreuer-me-tls` |

The four apps each use one Kubernetes Ingress on `websecure` with a cert-manager annotation. Traefik's entry-point redirect handles their HTTP requests globally; the four separate HTTP Ingresses and shared redirect Middleware were removed. The `HelmChartConfig` sets `allowACMEByPass: true`, so its global redirect excludes `/.well-known/acme-challenge/`; cert-manager's temporary HTTP-01 solver Ingress can answer those requests. A nonexistent challenge path returned 404 rather than redirecting; actual renewal after this change has not occurred yet. The redirect router has priority 1 so specific HTTP routers win. `felixbreuer.me` uses a Traefik `RedirectRegex` Middleware and HTTP/HTTPS `IngressRoute` objects backed by `noop@internal`; its HTTP route still sends one direct redirect to `https://breuer.dev/`. Its Certificate is explicit because cert-manager's ingress-shim watches Kubernetes Ingress objects, not Traefik IngressRoutes. The obsolete `grahamdigital/simple-redirect` pod and Service were removed after the native route and new certificate were ready.

## Verify

```bash
KUBECONFIG=temp/hetzner-kubeconfig kubectl get clusterissuer letsencrypt-prod
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n kube-system get helmchartconfig traefik
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get certificates,ingresses,ingressroutes,middlewares
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get deploy,pvc
curl -I http://danielkueffler.de/
curl -I http://stats.felixbreuer.me/
curl -I http://photos.felixbreuer.me/
curl -I https://danielkueffler.de/
curl -I https://stats.felixbreuer.me/
curl -I https://photos.felixbreuer.me/
curl -I http://screeps.felixbreuer.me/
curl -L -o /dev/null -w '%{http_code}\n' https://screeps.felixbreuer.me/
curl -fsS -o /dev/null -w '%{http_code}\n' https://screeps.felixbreuer.me/api/version
curl -I 'https://felixbreuer.me/path?x=1'
curl -I 'http://felixbreuer.me/path?x=1'
curl -I http://stats.felixbreuer.me/.well-known/acme-challenge/not-a-real-token
```

Expected: ClusterIssuer and five Certificates Ready; Ghost/Fathom/Noobgallery/Screeps Deployments 1/1; Ghost/Fathom/Screeps PVCs Bound; first three HTTPS routes return 200. Screeps `/` redirects to `/web/`, which returns 200; `/api/version` returns 200. HTTP app requests redirect to HTTPS, preserving path/query. Both `felixbreuer.me` schemes return `Location: https://breuer.dev/path?x=1` directly. A nonexistent ACME challenge path returns 404, not an HTTPS redirect. The HTTPS requests validate Let's Encrypt certificates without `curl -k`. Unknown HTTP hosts redirect globally; unknown HTTPS hosts return Traefik 404.

Ghost's homepage previously returned 200 while its active `t7394482` theme rendered bare links. After the approved switch to `edge`, verify its page visually as well as by status code: navigation and photo grid should display, with `/assets/built/screen.css` and post images loading. See [migration-runbook.md](migration-runbook.md).

If issuance fails, inspect `Certificate`, `CertificateRequest`, `Order`, and `Challenge` in `apps`; check DNS A/AAAA and public port 80. Do not apply certificates or private keys manually. Flux owns route manifests; cert-manager owns generated Secrets and renewals. A fresh-cluster restore recreates certificates from Git definitions and ACME, subject to DNS and rate limits. See [cert-manager.md](cert-manager.md).
