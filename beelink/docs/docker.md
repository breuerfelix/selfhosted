# Docker applications

Hermes and Hindsight run in Docker on Beelink. Docker remains installed and
enabled for these applications; Kubernetes applications use K3s containerd
and Flux separately.

## Deployment definition

The standalone Compose definition is `/opt/hermes/compose.json` on Beelink.
The directory has mode `0700` and the file has mode `0600`. It contains
application credentials; keep it on the host and out of Git.

```sh
ssh bee 'docker compose -p hermes -f /opt/hermes/compose.json config --quiet'
ssh bee 'docker ps -a'
```

Use project name `hermes` and that explicit file path for Compose operations.
Both services use the `hermes_default` network and host bind mounts; neither
uses a Docker volume.

| Container | Restart policy | Host ports | Persistent host paths |
| --- | --- | --- | --- |
| `hermes` | `always` | TCP 8642, 9119 | `/data/hermes`, `/data/hermes-backup` |
| `hindsight` | `unless-stopped` | TCP 8888, 9999 | `/data/hindsight`, including `/data/hindsight/codex` |

The host's Ansible playbooks configure Ubuntu updates and K3s. They do not
install Docker or deploy these two applications. Recover them separately using
the Compose definition, images, credentials, and retained host data.

## Health checks

```sh
ssh bee 'curl --fail --silent --output /dev/null http://127.0.0.1:9119/'
ssh bee 'curl --fail --silent --output /dev/null http://127.0.0.1:8888/health'
```

Inspect failures with `docker logs --tail 100 hermes` or
`docker logs --tail 100 hindsight` on the host. Logs can contain credentials;
avoid sharing raw output.
