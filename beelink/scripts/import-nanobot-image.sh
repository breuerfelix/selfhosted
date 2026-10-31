#!/usr/bin/env bash
set -euo pipefail

# Run locally after K3s bootstrap. This does not stop or start nanobot.
ssh bee bash -se <<'REMOTE'
set -euo pipefail
source_image=selfhosted-nanobot:0.4.0
expected_id=sha256:78f01703bf0e49dbcb57aea3ebf36499d13057f81b8ba95a95bbf9232a7312f4
target_image=docker.io/library/selfhosted-nanobot:0.4.0-78f01703bf0e
archive=/var/lib/rancher/k3s/agent/images/nanobot-0.4.0-78f01703bf0e.tar

test "$(docker image inspect "$source_image" --format '{{.Id}}')" = "$expected_id"
test "$(docker inspect nanobot --format '{{.Image}}')" = "$expected_id"
test -S /run/k3s/containerd/containerd.sock
install -d -m 0700 /var/lib/rancher/k3s/agent/images
docker image tag "$expected_id" "$target_image"
if ! test -f "$archive"; then
  trap 'rm -f "${archive}.partial"' EXIT
  docker image save --output "${archive}.partial" "$target_image"
  chmod 0600 "${archive}.partial"
  mv "${archive}.partial" "$archive"
fi
k3s ctr --namespace k8s.io images import "$archive"
k3s crictl inspecti "$target_image" >/dev/null
echo "Imported $target_image; archive retained for restart/recovery."
REMOTE
