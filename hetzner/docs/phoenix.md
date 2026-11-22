# Phoenix and OpenRouter Broadcast

## Deployment

- UI: <https://phoenix.felixbreuer.me>
- Public collector: `https://otel.felixbreuer.me/v1/traces`
- Phoenix project: `openrouter`
- SQLite: `/data/phoenix` on the Hetzner host, mounted at `/data` in Phoenix.

One Phoenix replica and one traces-only OpenTelemetry Collector run in `apps`.
OpenRouter sends OTLP/HTTP JSON; the collector exports OTLP/HTTP protobuf to the
private `http://phoenix` Service. It adds `openinference.project.name=openrouter`
without sampling or filtering spans. Only the collector's exact `/v1/traces`
path is exposed. Metrics, logs, collector gRPC, and collector metrics are not
enabled. Traefik terminates HTTPS and cert-manager renews the certificate.

Phoenix uses built-in authentication and secure cookies. The initial account is
`admin@localhost`, with a randomly generated password, not `admin`. The collector
uses a separate Phoenix provisioning secret internally; it has system-level API
access. Do not share it with OpenRouter. OpenRouter receives only `COLLECTOR_TOKEN`,
which authenticates ingestion but cannot read Phoenix data.

## Retrieve credentials securely

Run from the repository root on this Mac. These commands copy values directly to
the clipboard without printing them. Paste only into the intended login/settings
form or a password manager, never into chat. Clear the clipboard afterward.

```bash
export SOPS_AGE_KEY_FILE="$PWD/temp/hetzner-sops-age.key"

# Initial Phoenix login password; username: admin@localhost.
sops --decrypt --extract '["stringData"]["PHOENIX_DEFAULT_ADMIN_INITIAL_PASSWORD"]' \
  hetzner/cluster/apps/phoenix/secrets.sops.yaml | pbcopy

# Complete JSON for OpenRouter's Headers field.
sops --decrypt --extract '["stringData"]["COLLECTOR_TOKEN"]' \
  hetzner/cluster/apps/phoenix/secrets.sops.yaml \
  | python3 -c 'import json,sys; print(json.dumps({"Authorization": "Bearer " + sys.stdin.read().strip()}))' \
  | pbcopy

# Run after pasting and saving.
pbcopy </dev/null
```

The required header is `Authorization: Bearer <COLLECTOR_TOKEN>` (one space after
`Bearer`). This is neither an OpenRouter API key nor a Phoenix API key. If you
change the Phoenix login password in the UI, save the new password in your
password manager; the initial-password environment variable does not override
an already-customized password.

## Connect every OpenRouter workspace

Broadcast destinations are workspace-scoped. Repeat this entire setup in your
personal workspace and every organization/workspace whose requests you want to
capture. Organization changes require an administrator. Configuring one
workspace does not capture another workspace's requests.

1. Select the workspace in OpenRouter. Open
   [Settings → Observability](https://openrouter.ai/settings/observability) and
   turn on **Enable Broadcast**. Add/edit an **OpenTelemetry Collector**
   destination, not Arize AX.
2. Enter endpoint **`https://otel.felixbreuer.me/v1/traces`**. Paste the JSON
   copied above into **Headers**. Leave **Send OTLP metrics** off.
3. Set **Sampling Rate** to **1.0 / 100%**. Leave API-key inclusion and exclusion
   filters empty (all keys). Keep the destination enabled. Repeat for every
   workspace, including workspaces created later.
4. Set **Privacy Mode** deliberately: **off** captures prompts and responses;
   **on** removes prompt/completion content and provider error text. Metadata,
   usage, costs, and timing still travel. Privacy Mode is not full anonymization:
   custom metadata and request settings can still contain sensitive text.
5. Click **Test Connection**, then **Save**. OpenRouter will not save a destination
   whose test fails. Send a real API request using a key belonging to that
   workspace. Sign in to Phoenix, open **Projects → openrouter**, select a recent
   trace, and inspect its spans. Repeat with a request from each workspace.

The connection test is not proof of end-to-end persistence. A real request must
arrive in Phoenix. Compare its model, content (unless Privacy Mode is on), token
usage, and cost against the OpenRouter response/generation details. Do not assume
Phoenix's token/cost columns or price-derived totals match OpenRouter billing
until you have checked a real trace. This setup does not remap attributes or
recalculate costs.

## Operations and limits

Changes follow [maintenance.md](maintenance.md): validate, review, push to `main`,
and reconcile Flux. Ansible creates `/data/phoenix` only if absent, with `0:0`
ownership for the released image's default root user. Existing contents and
ownership are not modified. The PV uses `Directory`, an explicit claim, and
`Retain`; deleting its claim does not delete the directory.

```bash
export KUBECONFIG="$PWD/temp/hetzner-kubeconfig"
kubectl kustomize hetzner/cluster/apps >/dev/null
temp/ansible-venv/bin/ansible-playbook -i hetzner/ansible/inventory.ini \
  hetzner/ansible/storage.yml --syntax-check
flux reconcile kustomization apps --with-source --timeout=10m
kubectl -n apps get deploy/phoenix deploy/phoenix-collector pvc/phoenix-data
kubectl -n apps get certificate/phoenix-tls
kubectl -n apps logs deploy/phoenix-collector --tail=50

# Both must return 401, without disabling certificate validation.
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Content-Type: application/json' -d '{}' \
  https://otel.felixbreuer.me/v1/traces
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer invalid' -d '{}' \
  https://otel.felixbreuer.me/v1/traces
```

Secret changes require restarting both Deployments after Flux applies the Secret,
because their credentials come from environment variables. Rotating
`COLLECTOR_TOKEN` also requires updating every OpenRouter destination. Keep
`PHOENIX_SECRET` stable; changing it invalidates authentication tokens. No SMTP
password-recovery service is configured.

**100% sampling is not guaranteed delivery.** OpenRouter delivery failures,
finite retries, payload limits, a full disk, or downtime can lose traces. The
collector uses upstream batching/retry defaults and an in-memory queue, not a
durable spool; restarting it can lose buffered traces. One server and SQLite
provide no HA. Traces have infinite retention by default, and the PV's `10Gi`
declaration is not a disk quota. Retain does not protect against disk loss.
No ad hoc backups are created. This change does not extend the existing nightly
backup application's deployment allowlist to Phoenix.

## Official references

- [Phoenix architecture and SQLite](https://arize.com/docs/phoenix/self-hosting/architecture)
- [Phoenix OpenRouter Broadcast integration](https://arize.com/docs/phoenix/integrations/llm-providers/openrouter/openrouter-broadcast)
- [OpenRouter OpenTelemetry Collector destination](https://openrouter.ai/docs/guides/features/broadcast/otel-collector)
- [OpenRouter sampling, filtering, workspace scope, and privacy](https://openrouter.ai/docs/guides/features/broadcast)
- [Phoenix authentication](https://arize.com/docs/phoenix/self-hosting/features/authentication)
- [Phoenix provisioning](https://arize.com/docs/phoenix/self-hosting/features/provisioning)
