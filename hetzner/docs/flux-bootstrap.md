# Flux bootstrap: public Git repository

Flux reads `https://github.com/breuerfelix/selfhosted.git` anonymously. Its `GitRepository` has no `secretRef`; no GitHub token or deploy key is stored in the cluster. Local Git pushes still use the Mac's existing SSH access. The repository must remain public for this setup to work.

The reconciled path is `./hetzner/cluster`. The root `kustomization.yaml` names each cluster component explicitly. Add infrastructure and apps to that file only at later approved checkpoints. Initial sync contains Flux itself and starts no application workloads.

`flux install --export --components=source-controller,kustomize-controller,helm-controller` generated `gotk-components.yaml` using Flux CLI v2.9.6. `gotk-sync.yaml` contains a public HTTPS `GitRepository` and a self-reconciling Flux `Kustomization`. Generated components include Flux's default network policies. Do not hand-edit the large generated component file; regenerate it deliberately when upgrading Flux.

## Rebuild/bootstrap on a fresh K3s host

1. Run the host and K3s Ansible playbooks, restore an API-accessible kubeconfig, and ensure this repository is pushed to GitHub.
2. Apply the committed Flux components, wait for the custom resources to register, then apply the Git sync objects:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/flux-system/gotk-components.yaml
   KUBECONFIG=temp/hetzner-kubeconfig kubectl wait --for=condition=Established --timeout=120s crd/gitrepositories.source.toolkit.fluxcd.io crd/kustomizations.kustomize.toolkit.fluxcd.io
   KUBECONFIG=temp/hetzner-kubeconfig kubectl apply -f hetzner/cluster/flux-system/gotk-sync.yaml
   ```

3. Verify controllers and reconciliation:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/source-controller
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/kustomize-controller
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system rollout status deployment/helm-controller
   KUBECONFIG=temp/hetzner-kubeconfig flux check
   KUBECONFIG=temp/hetzner-kubeconfig flux get sources git
   KUBECONFIG=temp/hetzner-kubeconfig flux get kustomizations
   ```

No `flux bootstrap git` command is used: that command's SSH setup would generate a deploy key, which this public repository does not need.

The Flux `Kustomization` has `prune: true`. Removing a managed resource from Git will delete it from the cluster. Review deletion effects before merging future changes. App secrets will use SOPS with an age private key stored outside Git in a later stage.
