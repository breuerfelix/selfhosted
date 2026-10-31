#!/usr/bin/env python3
"""Validate the pinned source and emit GitHub Actions step outputs."""

import json
import os
from pathlib import Path
import re

source = json.loads(Path(__file__).with_name("source.json").read_text())
assert re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", source["repository"])
assert re.fullmatch(r"[0-9a-f]{40}", source["commit"])
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", source["version"])
assert re.fullmatch(r"ghcr\.io/[a-z0-9_.-]+/[a-z0-9_.-]+", source["image"])
for key in ("channels", "extras"):
    assert re.fullmatch(r"[a-z0-9_,-]*", source[key])
run = os.environ.get("GITHUB_RUN_ID", "local")
attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
assert re.fullmatch(r"[a-z0-9]+", run)
assert re.fullmatch(r"[0-9]+", attempt)
source["tag"] = f"{source['image']}:{source['version']}-{source['commit'][:12]}-{run}-{attempt}"
for key, value in source.items():
    print(f"{key}={value}")
