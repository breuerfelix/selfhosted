# Nanobot Google Workspace OAuth

The community `workspace-mcp` server runs inside the nanobot pod over stdio. Its OAuth callback uses `https://nanobot-workspace.vulture-skink.ts.net/oauth2callback`. A separate Tailscale Ingress terminates HTTPS and forwards that path to the pod on port 8000. The browser completing consent must be connected to Tailscale. No Funnel or LAN port is needed.

The Deployment supplies:

```text
WORKSPACE_MCP_BASE_URI=http://0.0.0.0
WORKSPACE_MCP_PORT=8000
GOOGLE_OAUTH_REDIRECT_URI=https://nanobot-workspace.vulture-skink.ts.net/oauth2callback
WORKSPACE_MCP_CREDENTIALS_DIR=/home/nanobot/.nanobot/auth/google-workspace
```

`0.0.0.0` binds the callback listener to the pod network. The public redirect stays HTTPS. Tokens persist on the existing nanobot PVC.

## Subprocess environment

The MCP Python SDK inherits only an allowlist of environment variables. Setting pod variables alone does not pass these four settings to `workspace-mcp`. The mutable `/home/nanobot/.nanobot/config.json` must also contain this server entry under `tools.mcpServers`, preserving any existing credentials and other servers:

```json
"google-workspace": {
  "type": "stdio",
  "command": "uvx",
  "args": ["workspace-mcp", "--transport", "stdio", "--tool-tier", "core"],
  "toolTimeout": 60,
  "env": {
    "WORKSPACE_MCP_BASE_URI": "${WORKSPACE_MCP_BASE_URI}",
    "WORKSPACE_MCP_PORT": "${WORKSPACE_MCP_PORT}",
    "GOOGLE_OAUTH_REDIRECT_URI": "${GOOGLE_OAUTH_REDIRECT_URI}",
    "WORKSPACE_MCP_CREDENTIALS_DIR": "${WORKSPACE_MCP_CREDENTIALS_DIR}"
  }
}
```

Nanobot resolves those references from the pod environment before starting the subprocess. Apps → MCP preserves the existing server environment when saving Google credentials. If the preset is removed and reinstalled, restore these four entries before authorizing.

## Connect the account

1. Enable the required Google APIs in your Google Cloud project.
2. Create or update a **Web application** OAuth client. Register exactly `https://nanobot-workspace.vulture-skink.ts.net/oauth2callback` under **Authorized redirect URIs**.
3. In nanobot, open **Apps → MCP → Google Workspace** and save the client ID and secret. Keep credentials out of Git.
4. Complete browser consent while connected to Tailscale. Confirm tokens appear under `/home/nanobot/.nanobot/auth/google-workspace` and a Google tool works.

The callback listener starts when workspace-mcp needs authorization. A closed port or proxy error before the server runs does not validate the OAuth setup. End-to-end verification requires the user's Google client and browser consent.
