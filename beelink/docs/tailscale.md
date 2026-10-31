# Tailscale operator authentication

The operator is managed by Flux from `cluster/infrastructure/tailscale`. Without `tailscale/operator-oauth`, its pod waits for the Secret and the HelmRelease/Kustomization are not Ready. Infinite install remediation allows recovery after credentials are added. Nanobot remains suspended throughout this setup.

## Steps on your Mac

1. Sign in to the existing tailnet in your browser. Open [Access controls](https://console.tailscale.com/admin/acls/file). Merge the entries below into the existing `tagOwners` object, preserving other policy sections and existing tag owners:

   ```json
   "tag:k8s-operator": [],
   "tag:k8s": ["tag:k8s-operator"]
   ```

2. Open [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials). Select **Credential → OAuth**, name it `beelink-k8s-operator`, and grant write scopes **General / Services**, **Devices / Core**, and **Keys / Auth Keys**, associated with `tag:k8s-operator`. Save the client ID and secret when shown; the secret is only shown once. A normal device auth key is not a replacement. [Official operator setup](https://tailscale.com/docs/kubernetes-operator/install-operator).

3. From a terminal on the Mac, run:

   ```bash
   python3 /Users/felix/code/selfhosted/beelink/scripts/configure-tailscale-oauth.py
   ```

   Enter the client ID and secret at the prompts. The secret input is hidden. The script passes credentials to SOPS in memory, writes only `cluster/infrastructure/tailscale/operator-oauth.sops.yaml`, and adds it to Kustomize resources. It uses the same public age recipient as Hetzner. It does not commit, push, or change the cluster. Do not paste credentials into chat.

4. Tell Codex the encrypted file is saved. Codex can then validate encryption/rendering, commit and push the two changed files, reconcile Flux, and verify the operator joins as `beelink-k8s-operator`.

5. Before exposing nanobot, enable **MagicDNS** and **HTTPS Certificates** under the tailnet's DNS settings. Ensure intended clients can reach `tag:k8s` on TCP 443 under the existing grants/ACLs. Keep Funnel disabled. No Pi-hole, global nameserver, subnet-route, or existing Docker Tailscale changes are needed.

## Enrollment verification

Use the Beelink kubeconfig for every command:

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
flux reconcile kustomization tailscale --with-source --timeout=10m
flux reconcile helmrelease tailscale-operator -n tailscale --timeout=10m
kubectl -n tailscale rollout status deployment/operator --timeout=300s
flux get kustomizations -A
flux get helmreleases -A
```

Confirm the operator appears in the tailnet's Machines list with `tag:k8s-operator`. Until nanobot is migrated, no app ingress/proxy exists. If device approval is required by the existing tailnet policy, approve the operator in the admin console. Do not mark authentication complete based only on the Helm chart being installed.

For later credential edits, use `SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key" sops beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml`. Preserve the age identity in its existing protected backup.
