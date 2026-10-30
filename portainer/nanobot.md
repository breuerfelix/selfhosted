# Nanobot on Portainer

Deploy `portainer/nanobot.yaml` as stack `nanobot`. It builds the official v0.4.0 Dockerfile at upstream commit `8f7a7d17590de7ab187650381894dba2b9e060ab`; upstream does not publish an official container image in its checked-in release workflows. Initial deployment requires Docker-host access to GitHub, npm, PyPI, and base-image registries.

## Access

Open `http://<docker-host>:8765`. First-boot logs contain the generated WebUI password. Treat those logs as sensitive. The password is persisted in `/data/nanobot/config.json` at `channels.websocket.tokenIssueSecret`. Use only a trusted LAN, SSH tunnel, or authenticated HTTPS proxy. Set Portainer stack variable `NANOBOT_BIND_IP` to a trusted interface or `127.0.0.1` to restrict publication. Docker port mappings can bypass host firewall rules; do not expose this port to the internet.

The gateway health endpoint is host-loopback-only at `http://127.0.0.1:18790/health`. No chat-channel credentials, Docker socket, or host filesystem access is enabled beyond nanobot's own data mount.

## OpenAI-compatible API

The `nanobot-api` service starts automatically with the stack and publishes port `8900` on the same interface selected by `NANOBOT_BIND_IP`. Base URL: `http://<docker-host>:8900/v1`. It supports `/v1/models` and `/v1/chat/completions` (including SSE streaming), not the complete OpenAI API surface. Send `Authorization: Bearer <api.apiKey>`; the generated key is stored in `/data/nanobot/config.json`, separately from Codex OAuth and the WebUI password. Inspect it locally through Portainer's container Console or Settings > System; never commit or paste it into chat. `/health` is intentionally unauthenticated.

The API uses the same persisted provider/configuration and OAuth login, with a separate persistent workspace at `/data/nanobot/api-workspace`. Its clients have agent/tool access, not merely model access. Keep port 8900 on a trusted LAN or put it behind HTTPS and access controls; do not forward it to the public internet. Only one user message per request is supported. Discover the fixed model ID using `/v1/models`; arbitrary upstream model selection is not supported.

For example, with the API key already set securely in your client shell:

```sh
curl --fail http://<docker-host>:8900/v1/models \
  -H "Authorization: Bearer $NANOBOT_API_KEY"
curl --fail http://<docker-host>:8900/v1/chat/completions \
  -H "Authorization: Bearer $NANOBOT_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"session_id":"example"}'
```

API configuration is loaded at process startup. After changing provider, model, or API settings, run `docker restart nanobot-api`. Do not also start the API from WebUI Settings > System: Compose already manages the listener. Upstream API behavior and compatibility limitations are documented in [openai-api.md](https://github.com/HKUDS/nanobot/blob/v0.4.0/docs/openai-api.md).

## Codex subscription login

Nanobot has native OpenAI Codex subscription OAuth; do not install the Codex CLI or configure a separately billed OpenAI API key.

Recommended: open Settings > Models in the WebUI, select OpenAI Codex, and complete its sign-in flow. Alternatively, run on the Docker host:

```sh
docker exec -it --user nanobot nanobot nanobot provider login openai-codex --set-main
```

For Portainer's container Console, select container `nanobot`, set user `nanobot`, connect with `/bin/bash`, then run:

```sh
nanobot provider login openai-codex --set-main
```

Open the authorization URL in your browser. For remote login, follow the CLI's prompt for the complete redirected localhost callback URL; paste it only into the container terminal, never into chat. A localhost callback error in the browser is expected when the browser and container are different machines. No callback port needs to be published.

After terminal-based configuration, restart both nanobot services to load it and verify a real completion:

```sh
docker restart nanobot nanobot-api
docker exec --user nanobot nanobot nanobot agent -m "Reply with exactly NANOBOT_OK"
```

The WebUI can enumerate the account's available Codex models. Use the `openai_codex` provider, not the direct API provider `openai`.

## Persistence and host credential reuse

The bind mount `/data/nanobot:/home/nanobot/.nanobot` persists configuration, workspace, conversations, and credentials. `XDG_DATA_HOME=/home/nanobot/.nanobot/data` explicitly keeps oauth-cli-kit's files inside that mount. Codex credentials therefore live at `/data/nanobot/data/oauth-cli-kit/auth/codex.json` on the host. Always use `--user nanobot` for exec commands; Docker exec otherwise inherits the image's bootstrap root user.

The existing `/data/hindsight/codex/auth.json` has Codex CLI OAuth structure. Nanobot's oauth-cli-kit can import `$HOME/.codex/auth.json`, so a read-only mount of that directory to `/home/nanobot/.codex` would technically seed nanobot's own OAuth cache. It does not synchronize later refreshes back to the CLI file; independent refreshers can invalidate shared refresh tokens. Consequently this stack deliberately uses a separate OAuth login and does not mount or modify Hindsight/Hermes credentials. `CODEX_HOME` alone does not configure this library's import path.

To back up or migrate nanobot, stop its writers and preserve the complete `/data/nanobot` tree, including auth and SQLite sidecar files. Do not commit its contents. The existing restic backup scope has not been changed by this stack.

Sources: [upstream deployment](https://github.com/HKUDS/nanobot/blob/v0.4.0/docs/deployment.md), [provider instructions](https://github.com/HKUDS/nanobot/blob/v0.4.0/docs/providers.md#oauth-providers), and installed oauth-cli-kit 0.1.6 `storage.py`.
