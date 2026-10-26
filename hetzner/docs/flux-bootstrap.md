# Flux bootstrap: public Git repository

Flux reads `https://github.com/breuerfelix/selfhosted.git` anonymously. Its `GitRepository` has no `secretRef`; no GitHub token or deploy key is stored in the cluster. Local Git pushes still use the Mac's existing SSH access. The repository must remain public for this setup to work.

The reconciled path is `./hetzner/cluster`. The root `kustomization.yaml` names each cluster component explicitly. The original bootstrap contained only Flux; current Git includes storage, cert-manager, Traefik routing, and active apps. Add new components only at approved checkpoints.

`flux install --export --components=source-controller,kustomize-controller,helm-controller` generated `gotk-components.yaml` using Flux CLI v2.9.6. `gotk-sync.yaml` contains a public HTTPS `GitRepository` and a self-reconciling Flux `Kustomization`. Generated components include Flux's default network policies. Do not hand-edit the large generated component file; regenerate it deliberately when upgrading Flux.

## Rebuild/bootstrap on a fresh K3s host

1. Run the host and K3s Ansible playbooks, restore Ghost/Fathom data to `/srv/k3s-data`, restore an API-accessible kubeconfig, and ensure this repository is pushed to GitHub. Wait for K3s-packaged Traefik and its CRDs; the Git sync contains Traefik Middleware and IngressRoute resources:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n kube-system rollout status deployment/traefik --timeout=300s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl wait --for=condition=Established --timeout=120s crd/middlewares.traefik.io crd/ingressroutes.traefik.io
   ```

2. Apply the committed Flux components, wait for their custom resources and controllers, then bootstrap the committed cert-manager source and release. cert-manager must install its CRDs before the Git sync applies the `ClusterIssuer` and explicit `Certificate`:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/flux-system/gotk-components.yaml
   KUBECONFIG=temp/hetzner-kubeconfig kubectl wait --for=condition=Established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io crd/ocirepositories.source.toolkit.fluxcd.io crd/helmreleases.helm.toolkit.fluxcd.io
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/source-controller --timeout=180s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/kustomize-controller --timeout=180s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/helm-controller --timeout=180s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/infrastructure/cert-manager/namespace.yaml
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/infrastructure/cert-manager/chart.yaml
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/infrastructure/cert-manager/release.yaml
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n cert-manager wait --for=condition=Ready ocirepository/cert-manager --timeout=180s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n cert-manager wait --for=condition=Ready helmrelease/cert-manager --timeout=300s
   KUBECONFIG=temp/hetzner-kubeconfig kubectl wait --for=condition=Established --timeout=120s crd/clusterissuers.cert-manager.io crd/certificates.cert-manager.io
   ```

3. Restore the SOPS age identity from password manager to ignored `temp/hetzner-sops-age.key` (mode `0600`), then create `flux-system/sops-age` before Git sync. Flux takes over cert-manager and applies remaining manifests from Git. Wait for cert-manager to issue certificates once public DNS and ports 80/443 reach Traefik:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=temp/hetzner-sops-age.key
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/flux-system/gotk-sync.yaml
   KUBECONFIG=temp/hetzner-kubeconfig flux reconcile source git flux-system -n flux-system
   KUBECONFIG=temp/hetzner-kubeconfig flux reconcile kustomization flux-system -n flux-system
   ```

   The root sync also applies system-upgrade-controller and its Plan CRD. It creates a separate `flux-system/k3s-upgrade-plan` Kustomization which waits for root readiness before applying the 04:00 patch Plan. No manual Plan apply is needed on a fresh host.

4. Verify controllers and reconciliation:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/source-controller
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/kustomize-controller
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/helm-controller
   KUBECONFIG=temp/hetzner-kubeconfig flux check
   KUBECONFIG=temp/hetzner-kubeconfig flux get sources git
   KUBECONFIG=temp/hetzner-kubeconfig flux get kustomizations
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n system-upgrade get deploy,plan
   ```

No `flux bootstrap git` command is used: that command's SSH setup would generate a deploy key, which this public repository does not need.

The Flux `Kustomization` has `prune: true`. Removing a managed resource from Git will delete it from the cluster. Review deletion effects before merging future changes. Its SOPS age private key lives in a manually created `flux-system/sops-age` Secret outside Git; see [secrets.md](secrets.md) for recovery.
