# Prepared application manifests

Five app directories under `hetzner/cluster/apps/` were prepared for migration. Ghost, Fathom, Noobgallery, and Screeps now run as Deployments with ClusterIP Services and public HTTPS routes. The redirect directory contains a Traefik route and Certificate, with no Deployment or Service. Travian inactive finder and idle proxy were removed from migration scope at user request; their old Coolify containers remain stopped until final teardown. This document records initial preparation and activation; see [ingress.md](ingress.md) for current routing.

| Directory | Container port | State | Image pin |
| --- | ---: | --- | --- |
| `ghost` | 2368 | Existing `ghost-content` PVC; one replica, `Recreate` | Exact `5.130.6-alpine` tag and current digest |
| `fathom` | 8080 | Existing `fathom-data` PVC; one replica, `Recreate` | Exact `version-1.2.1` tag and current digest |
| `screeps` | 21025 | New, unbacked-up `local-path` PVC; encrypted config Secret; one replica, `Recreate` | Exact `v1.17.0` tag and current digest |
| `redirect` | — | Traefik `IngressRoute` and Middleware; no pod | No image |
| `noobgallery` | 80 | None | Only `latest` tag published; current digest pinned |

Image digests were copied from images used by stopped Coolify containers and checked against public registries. `tag@sha256:digest` is immutable at deployment even when tag text says `latest`. Root `renovate.json` now tells the Kubernetes manager to inspect `hetzner/cluster/apps/**/*.yaml` and gives Fathom's `version-1.2.1` tag an explicit version parser, so Renovate can propose tag and digest updates. Review updates before merging; merging an activated app's image change will roll its Deployment.

Ghost and Fathom environment values match stopped Coolify Compose definitions, including Ghost `NODE_ENV=development` and Fathom `FATHOM_DEBUG=true`. Historical redirect values were `PROTOCOL=http`, `REDIRECT_TO=breuer.dev`; the old image ignored `PROTOCOL`, so the live route now uses Traefik to redirect directly to HTTPS. Screeps uses the nonempty live config from Coolify's UUID directory, not the empty alternate config path. Its original `version: latest` selected Screeps package `4.3.0` on first start. The encrypted config now pins `version: 4.3.0`, and the Deployment template annotation triggers a restart when that selected package version changes. Launcher image remains pinned by tag and digest.

Application Services are internal ClusterIP endpoints; Traefik exposes them. TCP readiness checks indicate whether the configured port accepts connections. Ghost/Fathom passed HTTP and selected data checks. Noobgallery returned HTTP 200 for its page, an image, and CSS. Screeps returned HTTP 200 for `/api/version` and `/web/`; authenticated gameplay was not tested. First launch compiled native packages and took about five minutes. No liveness probes or resource limits were guessed from absent Coolify settings. Old Coolify data and containers remain for rollback.

## Activation history

Ghost and Fathom were activated first at revision `9fdc994`; redirect and Noobgallery followed at `6d61d63`. All four passed internal port-forward checks. The redirect pod was later removed in favor of Traefik. Screeps was added to `hetzner/cluster/kustomization.yaml` at `10fd28a`, package version pinned at `475ff88`, restarted with its pinned config at `aadce92`, and exposed publicly at `0235a7a`. Flux reconciled its encrypted Secret, Deployment, 3Gi disposable PVC, and HTTPS/HTTP Ingresses. Old Screeps world data was not copied; its old Coolify folders remain untouched. All five routes have valid production certificates.
