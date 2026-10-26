# cert-manager checkpoint

Installed 2026-10-26 through Flux at `hetzner/cluster/infrastructure/cert-manager/`. A later checkpoint added production `ClusterIssuer/letsencrypt-prod` with ACME contact `felix@breuer.dev`. Ghost, Fathom, Noobgallery, Screeps, and `felixbreuer.me` certificates are Ready. See [ingress.md](ingress.md) for routes.

The OCI chart is `quay.io/jetstack/charts/cert-manager:v1.21.3`, pinned to manifest digest `sha256:e482675aec32862d323a9218293ff7de81192337998615e4378c56498473f240`. Flux's `OCIRepository` copies the Helm chart layer and the `HelmRelease` installs it in the `cert-manager` namespace with `crds.enabled: true`. Chart values pin controller, webhook, cainjector, HTTP-01 solver, and startup API check images to version `v1.21.3` plus digests. Renovate's Flux manager scans this directory; review chart and image updates together for compatibility before merging. cert-manager v1.21 supports and tests Kubernetes 1.36.

Source: https://cert-manager.io/docs/installation/helm/ and https://cert-manager.io/docs/releases/

## Verify

From repository root, with ignored Mac kubeconfig:

```bash
KUBECONFIG=temp/hetzner-kubeconfig flux get sources oci -n cert-manager
KUBECONFIG=temp/hetzner-kubeconfig flux get helmreleases -n cert-manager
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n cert-manager get deployments,pods
KUBECONFIG=temp/hetzner-kubeconfig kubectl get crd | rg 'cert-manager.io'
KUBECONFIG=temp/hetzner-kubeconfig kubectl get --raw /apis/cert-manager.io/v1
KUBECONFIG=temp/hetzner-kubeconfig kubectl get clusterissuer letsencrypt-prod
KUBECONFIG=temp/hetzner-kubeconfig kubectl -n apps get certificates
KUBECONFIG=temp/hetzner-kubeconfig kubectl get ingress -A
```

Expected now: OCIRepository and HelmRelease Ready; three cert-manager deployments 1/1; six cert-manager CRDs; API discovery succeeds; production ClusterIssuer Ready; five Certificates Ready. The Helm chart's startup API check completes during installation. Do not apply the chart manually: Flux owns its lifecycle.

## Rebuild

After K3s and Flux are restored from Git, this directory recreates cert-manager and the issuer automatically. ACME account key is generated in a Kubernetes Secret in the cert-manager namespace; certificate private keys are generated in `apps` TLS Secrets. Those generated Secrets are not committed to Git or included in the current Ghost/Fathom file backup. On a fresh cluster, cert-manager will register a new ACME account and issue new certificates after DNS and public port 80 work; allow for ACME rate limits. HTTP-01 uses K3s-packaged Traefik's `traefik` IngressClass. The Git-managed Traefik `HelmChartConfig` exempts `/.well-known/acme-challenge/` from its global HTTP-to-HTTPS redirect, so temporary solver Ingresses can answer on port 80. Screeps' public route is Git-managed and reconciles with the other app routes. Certificate renewal under the new global redirect has not yet occurred.
