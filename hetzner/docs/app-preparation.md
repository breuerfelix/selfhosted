# Prepared application manifests

Five app directories under `hetzner/cluster/apps/` contain Deployments and ClusterIP Services. `ghost`, `fathom`, `redirect`, and `noobgallery` are included in the live `hetzner/cluster/kustomization.yaml` and running internally. `screeps` remains inactive. No ingress is deployed. Travian inactive finder and idle proxy were removed from migration scope at user request; their old Coolify containers remain stopped until final teardown.

| Directory | Container port | State | Image pin |
| --- | ---: | --- | --- |
| `ghost` | 2368 | Existing `ghost-content` PVC; one replica, `Recreate` | Exact `5.130.6-alpine` tag and current digest |
| `fathom` | 8080 | Existing `fathom-data` PVC; one replica, `Recreate` | Exact `version-1.2.1` tag and current digest |
| `screeps` | 21025 | New, unbacked-up `local-path` PVC; encrypted config Secret; one replica, `Recreate` | Exact `v1.17.0` tag and current digest |
| `redirect` | 80 | None | Only `latest` tag published; current digest pinned |
| `noobgallery` | 80 | None | Only `latest` tag published; current digest pinned |

Image digests were copied from images used by stopped Coolify containers and checked against public registries. `tag@sha256:digest` is immutable at deployment even when tag text says `latest`. Root `renovate.json` now tells the Kubernetes manager to inspect `hetzner/cluster/apps/**/*.yaml` and gives Fathom's `version-1.2.1` tag an explicit version parser, so Renovate can propose tag and digest updates. Review updates before merging; merging an activated app's image change will roll its Deployment.

Ghost and Fathom environment values match stopped Coolify Compose definitions, including Ghost `NODE_ENV=development` and Fathom `FATHOM_DEBUG=true`. Redirect values were recovered from its stopped container: `PROTOCOL=http`, `REDIRECT_TO=breuer.dev`. Screeps uses the nonempty live config from Coolify's UUID directory, not the empty alternate config path. That file still selects `version: latest` for the Screeps application package; only its container image is pinned in this stage. Revisit that package selector if automatic package changes cause trouble.

Each Service is internal only. TCP readiness checks indicate whether the configured port accepts connections. Ghost/Fathom passed HTTP and selected data checks. Redirect returned HTTP 301 to `http://breuer.dev/`, matching stopped Coolify settings. Noobgallery returned HTTP 200 for its page, an image, and CSS. Screeps remains untested. No liveness probes or resource limits were guessed from absent Coolify settings. Old Coolify data and containers remain for rollback.

## Later activation

Ghost and Fathom were activated first at revision `9fdc994`; redirect and Noobgallery followed at `6d61d63`. All four passed internal port-forward checks. Add Screeps to `hetzner/cluster/kustomization.yaml` only after a separate review. The SOPS age key is installed in Flux, but encrypted Screeps config has not yet been reconciled. Ingress and TLS remain separate stages. Review whether redirect should continue using HTTP before exposing its route publicly.
