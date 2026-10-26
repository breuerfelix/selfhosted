# cert-manager checkpoint

Installed 2026-10-26 through Flux at `hetzner/cluster/infrastructure/cert-manager/`. This checkpoint installs only cert-manager. There is no `Issuer`, `ClusterIssuer`, `Certificate`, or application `Ingress` yet; public HTTP still reaches Traefik's default 404 handler.

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
KUBECONFIG=temp/hetzner-kubeconfig kubectl get ingress -A
```

Expected now: OCIRepository and HelmRelease Ready; three deployments 1/1 and pods without restarts; six cert-manager CRDs; API discovery succeeds; no application Ingress. The Helm chart's startup API check completes during installation. Do not apply the chart manually: Flux owns its lifecycle.

## Rebuild and next stage

After K3s and Flux are restored from Git, this directory recreates cert-manager automatically. Its current state has no ACME account key or certificate material to restore. Later, place issuer and application Ingress manifests in Git only after cert-manager CRDs and webhook are Ready. HTTP-01 will use K3s-packaged Traefik's `traefik` IngressClass on public port 80. Check all intended hosts' A/AAAA records, firewall rules, and ACME contact address before requesting production certificates. Keep Screeps' route absent until its workload starts.
