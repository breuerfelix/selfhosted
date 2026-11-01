#!/usr/bin/env bash
set -euo pipefail
image=${1:?Pass the built image reference}
container=nanobot-image-smoke
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT

# Isolated writable state; no production mount, credentials, or outbound network.
docker run --detach --name "$container" --network none \
  --user 1000:1000 \
  --tmpfs /home/nanobot/.nanobot:rw,uid=1000,gid=1000,mode=0700 \
  --env NANOBOT_DOCKER_BOOTSTRAP=1 \
  --env NANOBOT_WEB_TOKEN=ci-smoke-test-only \
  --env NANOBOT_API_KEY=ci-smoke-test-only \
  --env XDG_DATA_HOME=/home/nanobot/.nanobot/data \
  "$image" gateway >/dev/null

# Run directly so a missing CLI fails immediately with a useful error.
docker exec --user 1000:1000 "$container" gh --version

for attempt in $(seq 1 60); do
  if docker exec "$container" python -c '
import os, pathlib, urllib.request
assert os.getuid() == 1000
assert pathlib.Path("/app/nanobot/web/dist/index.html").is_file()
assert urllib.request.urlopen("http://127.0.0.1:18790/health", timeout=4).status == 200
r = urllib.request.urlopen("http://127.0.0.1:8765/", timeout=4)
assert r.status == 200 and "text/html" in r.headers.get("Content-Type", "")
' >/dev/null 2>&1; then
    echo "Nanobot gateway, WebUI, bundled assets, GitHub CLI, and non-root smoke test passed."
    exit 0
  fi
  if test "$(docker inspect "$container" --format '{{.State.Running}}')" != true; then
    break
  fi
  sleep 2
done
docker logs "$container"
echo "Nanobot smoke test failed." >&2
exit 1
