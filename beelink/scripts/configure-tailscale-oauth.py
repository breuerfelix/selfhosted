#!/usr/bin/env python3
"""Prompt locally and save a SOPS-encrypted operator Secret without plaintext files."""

import getpass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    repo = Path(__file__).resolve().parents[2]
    directory = repo / "beelink/cluster/infrastructure/tailscale"
    target = directory / "operator-oauth.sops.yaml"
    kustomization = directory / "kustomization.yaml"
    if target.exists():
        sys.exit(f"Secret already exists. Edit it with sops: {target}")

    print("Tailscale OAuth client ID: ", end="", file=sys.stderr, flush=True)
    with open("/dev/tty", encoding="utf-8") as tty:
        client_id = tty.readline().strip()
    client_secret = getpass.getpass("Tailscale OAuth client secret (hidden): ").strip()
    if not client_id or not client_secret:
        sys.exit("Client ID and secret must both be nonempty.")

    secret = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "operator-oauth", "namespace": "tailscale"},
        "type": "Opaque",
        "stringData": {"client_id": client_id, "client_secret": client_secret},
    }
    result = subprocess.run(
        [
            "sops", "--config", str(repo / "beelink/.sops.yaml"),
            "encrypt", "--input-type", "json", "--output-type", "yaml",
            "--filename-override", str(target), "/dev/stdin",
        ],
        input=json.dumps(secret), text=True, capture_output=True,
    )
    if result.returncode:
        # Keep subprocess output out of logs: input contains real credentials.
        sys.exit("SOPS encryption failed; no Secret was written. Check sops installation and config.")

    fd, temporary = tempfile.mkstemp(prefix=".operator-oauth-", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(result.stdout)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

    content = kustomization.read_text()
    entry = "  - operator-oauth.sops.yaml"
    if entry not in content.splitlines():
        comment = "  # Add operator-oauth.sops.yaml here before enabling tailscale-sync."
        if comment in content:
            content = content.replace(comment, entry)
        else:
            content = content.rstrip() + "\n" + entry + "\n"
        kustomization.write_text(content)
    print(f"Saved encrypted Secret: {target}")
    print("Kustomization updated. No plaintext file, commit, push, or cluster change was made.")
    print("Tell Codex the credentials are saved so it can review, publish, and verify enrollment.")


if __name__ == "__main__":
    main()
