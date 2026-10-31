#!/usr/bin/env python3
"""Pin a successful CI build in the Deployment without changing suspension."""

from pathlib import Path
import re
import sys

image = sys.argv[1]
if not re.fullmatch(r"ghcr\.io/breuerfelix/nanobot@sha256:[0-9a-f]{64}", image):
    sys.exit("Expected the nanobot GHCR image with a complete sha256 digest.")
path = Path(__file__).resolve().parents[2] / "cluster/apps/nanobot/app.yaml"
content = path.read_text()
content, count = re.subn(r"(?m)^          image: .*?$", f"          image: {image}", content)
assert count == 1
content = content.replace(
    "          # Import this exact existing Docker image before enabling the sync.",
    "          # Built from the upstream commit in beelink/images/nanobot/source.json.",
)
content = content.replace("          imagePullPolicy: Never", "          imagePullPolicy: IfNotPresent")
path.write_text(content)
print(f"Pinned {image}")
