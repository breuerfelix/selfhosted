# Phoenix on Hetzner

## Intent and constraints

Capture personal OpenRouter traffic with 100% sampling in one authenticated Phoenix instance. Use one SQLite writer, one traces-only OpenTelemetry Collector, existing Traefik/cert-manager, Flux, and SOPS-age. No extra databases, monitoring, operators, scheduling rules, or ad hoc backups.

## Approaches

The user selected Phoenix plus a collector. Official Phoenix and OpenRouter documentation confirms OTLP/HTTP JSON must be converted to protobuf. Direct ingestion is incompatible; a database service adds no value for this single-user deployment.

## Design

- Phoenix `version-22.0.1` and Collector `0.165.0`, pinned by digest, each with one replica.
- Phoenix uses `Recreate`, `/data/phoenix`, and a retained hostPath PV with `type: Directory` and an explicitly bound claim. Ansible creates the directory only if absent and leaves existing ownership unchanged.
- UI: `https://phoenix.felixbreuer.me`, built-in authentication, generated non-default admin password, secure cookies, and a persistent signing secret. No external identity provider or SMTP.
- Collector: `https://otel.felixbreuer.me/v1/traces`, exact ingress path, bearer authentication, HTTP receiver only, traces pipeline only, private/disabled internal telemetry. Set project `openrouter`; export protobuf through Phoenix's ClusterIP Service using a separate provisioned bearer secret.
- Credentials are generated locally without printing and stored only in SOPS-encrypted Kubernetes Secrets. No credentials are requested from the user unless needed.
- Keep upstream retry/batch defaults; the collector queue is not durable. Sampling all requests is not guaranteed delivery. SQLite retains traces indefinitely by default and shares the server disk.

## Verification and handoff

Validate Kustomize, Ansible syntax, decrypted resources against the API server, and collector configuration. Deploy through reviewed Git on `main` and Flux. Verify readiness, volume binding, HTTPS, login, rejected missing/wrong ingestion tokens, successful synthetic JSON ingestion, and trace survival after Phoenix restart. Document OpenRouter configuration for every workspace, sampling, filters, privacy mode, and a real-request check. Do not claim real token/cost display until verified.

Host access and OpenRouter account configuration are external prerequisites. The repository's wildcard DNS already resolves both hosts to Hetzner.
