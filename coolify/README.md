# Coolify export

Snapshot of the current Coolify-managed applications.

Notes:
- This repository import does not change the live Coolify resources.
- Application settings are exported from the Coolify API into `app.json`.
- Environment variable keys and metadata are exported into `envs.redacted.json`, but values are intentionally replaced with `[REDACTED]` before commit.
- Coolify-generated runtime labels are omitted from the committed export because they are derived control-plane data, not source-of-truth config.
