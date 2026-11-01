# Tailscale operator

Flux manages the operator under `cluster/infrastructure/tailscale`. The encrypted `operator-oauth.sops.yaml` Secret supplies `client_id` and `client_secret`; credentials are not Helm values. Its tailnet hostname is `beelink-k8s-operator`.

## Tailnet prerequisites

Merge these entries into the existing `tagOwners` object under [Access controls](https://console.tailscale.com/admin/acls/file), preserving other policy sections:

```json
"tag:k8s-operator": [],
"tag:k8s": ["tag:k8s-operator"]
```

Enable MagicDNS and HTTPS Certificates in the tailnet DNS settings. Allow intended clients to reach `tag:k8s` on TCP 443. Keep Funnel disabled for these private apps. Each Tailscale Ingress creates an HTTPS proxy for its declared hostname; no public reverse proxy or router port forwarding is required.

## OAuth credentials

Create an OAuth client under [Trust credentials](https://console.tailscale.com/admin/settings/trust-credentials) with write scopes **General / Services**, **Devices / Core**, and **Keys / Auth Keys**, associated with `tag:k8s-operator`. Use the [official operator setup](https://tailscale.com/docs/kubernetes-operator/install-operator) to check available scopes. Store the client secret securely when shown.

Edit the existing encrypted Secret from the repository root:

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"
sops beelink/cluster/infrastructure/tailscale/operator-oauth.sops.yaml
```

Update `stringData.client_id` and `stringData.client_secret` in the SOPS editor. Saving encrypts both values; keep plaintext credentials out of Git and chat. Push the reviewed encrypted change, then reconcile and restart the operator:

```bash
export KUBECONFIG="$PWD/temp/beelink-kubeconfig"
flux reconcile kustomization tailscale --with-source --timeout=10m
kubectl -n tailscale rollout restart deployment/operator
kubectl -n tailscale rollout status deployment/operator --timeout=300s
flux reconcile helmrelease tailscale-operator -n tailscale --timeout=10m
```

The operator requires this Secret to start. Unlimited Helm install remediation allows recovery after credentials become available. Confirm enrollment in the tailnet Machines list with `tag:k8s-operator`, approve the device if policy requires it, and verify an app's HTTPS route with certificate validation.
