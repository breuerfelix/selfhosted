# SOPS age key and application secrets

The private age identity is on this Mac at `/Users/felix/code/selfhosted/temp/hetzner-sops-age.key` (mode `0600`, ignored by Git). **Save the complete contents of this exact file in a password manager now.** The age recipient in `hetzner/cluster/apps/.sops.yaml` is public and safe in Git. No private key or plaintext app secret is committed.

An identical copy of the age identity is in the manually created `flux-system/sops-age` Kubernetes Secret under key `age.agekey`. The Flux self-reconciling Kustomization in `hetzner/cluster/flux-system/gotk-sync.yaml` declares `decryption.provider: sops` and references that Secret. When an encrypted Secret manifest enters the live cluster Kustomization, Flux decrypts it and applies an ordinary Kubernetes Secret. SOPS protects Git; the cluster has the key and decrypted data.

The existing Screeps config was copied to ignored `temp/screeps-config.yml`, wrapped as a Kubernetes Secret, and encrypted at `hetzner/cluster/apps/screeps/config.sops.yaml`. Local decryption was checked against the original file. Temporary plaintext Screeps and redirect environment copies were then removed from `temp/`; the original stopped Coolify files remain on the VPS. The encrypted file is staged for later deployment; its app directory is not yet included in `hetzner/cluster/kustomization.yaml`.

## Fresh cluster recovery

1. Restore the private identity from the password manager to an ignored local file with mode `0600`.
2. Bootstrap Flux and create its decryption Secret before enabling encrypted apps:

   ```bash
   KUBECONFIG=temp/hetzner-kubeconfig kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=temp/hetzner-sops-age.key
   ```

3. Confirm Flux reconciles. If an encrypted app fails to decrypt, check presence of `flux-system/sops-age` and the `decryption` reference without printing Secret contents.

Losing all copies of the private age identity prevents decryption of committed secrets. Restore or regenerate application credentials and re-encrypt if that happens. Do not commit the private key, Mac kubeconfig, or plaintext Screeps config. The ignored `temp/` directory is not part of a fresh checkout.

References: https://fluxcd.io/flux/guides/mozilla-sops/ and https://fluxcd.io/flux/components/kustomize/kustomizations/
