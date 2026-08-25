# Monitoring stack

`monitoring.yaml` runs Grafana, VictoriaMetrics, Loki, and the Beelink host collector.
The collector path is:

```text
cAdvisor -> vmagent -> VictoriaMetrics <- Grafana
```

## Deployment inputs

The Portainer stack uses the Git repository's `portainer/monitoring.yaml` file.
The vmagent scrape configuration is inlined in its Compose `configs` entry because
Portainer Git stacks do not materialize relative `configs.file` paths. The source
copy at `portainer/vmagent/prometheus.yml` documents the same configuration, but
the deployed stack does not require a host-side configuration file. The Grafana
dashboard is managed directly in Grafana and is intentionally not provisioned
from this repository.

Set the existing Grafana secret before deploying or updating the stack:

```text
GF_SECURITY_ADMIN_PASSWORD=<value>
```

The stack creates or uses these host directories for persistent data:

- `/data/grafana`
- `/data/victoriametrics`
- `/data/loki`
- `/data/vmagent`

The Docker host running Portainer (the Beelink) must allow the cAdvisor mounts in
`monitoring.yaml`. They are read-only except for vmagent's local retry buffer and
the existing service data directories. The Docker socket is mounted read-only;
cAdvisor and vmagent are not exposed on host ports.

## Metrics

The `beelink-cadvisor` scrape job targets `cadvisor:8080` on the private
`monitoring_monitoring` network and adds the stable labels `host="beelink"` and
`service="cadvisor"`. vmagent forwards the Prometheus-format metrics to
`http://victoriametrics:8428/api/v1/write` and buffers unsent samples under
`/data/vmagent` while VictoriaMetrics is unavailable.

cAdvisor supplies both Docker container statistics and machine/filesystem
metrics from the Beelink. A separate node-exporter is intentionally not included:
the current stack has no host-exporter convention, and cAdvisor covers the host
and container metrics required here without another privileged collector.

## Verification

After the stack is running, verify the collector path from the host or Portainer:

1. Check that `cadvisor`, `vmagent`, and `victoriametrics` are running.
2. From the monitoring network, confirm cAdvisor responds at `http://cadvisor:8080/metrics`.
3. Confirm vmagent's target for job `beelink-cadvisor` is up and its remote-write queue is healthy.
4. Query VictoriaMetrics for a non-empty host series, for example
   `machine_memory_bytes{host="beelink"}`, and a container series such as
   `container_cpu_usage_seconds_total{host="beelink"}`.
5. For a concrete scrape-health check, query these PromQL expressions through the
   configured VictoriaMetrics datasource:

   ```promql
   up{job="beelink-cadvisor",host="beelink",instance="cadvisor:8080",service="cadvisor"}
   machine_scrape_error{host="beelink"}
   container_scrape_error{host="beelink"}
   machine_memory_bytes{host="beelink"}
   machine_cpu_cores{host="beelink"}
   count(container_cpu_usage_seconds_total{host="beelink"})
   ```

   Expected results are `up = 1`, both scrape-error gauges `= 0`, non-zero
   machine memory and CPU-core values, and a positive container-series count.
   A range query such as
   `up{job="beelink-cadvisor"}[30m]` should contain repeated samples, all `1`;
   this catches intermittent target failures that an instant query can miss.
6. Redeploy or restart the stack and repeat the checks; `/data/victoriametrics`
   and `/data/vmagent` must remain intact.

## Restart and persistence procedure

Use Portainer on the Docker host (`local`, environment ID `3`) for the
restart exercise. Do not enter the Grafana password in shell history or task
comments.

1. Before starting stack `monitoring` (stack `26`), set its existing
   `GF_SECURITY_ADMIN_PASSWORD` environment value in Portainer. The Compose
   expression is required and intentionally fails closed when this value is
   absent.
2. Deploy the repository revision containing the inline
   `vmagent-scrape-config` (`configs.content`). Portainer Git stacks do not
   materialize the relative `configs.file` form. Until that revision is on
   the configured Git ref, keep stack `monitoring-collector` (`36`) running as
   the persistent vmagent workaround.
3. Do not run both stacks with a `vmagent` service at once: both use the
   container name `vmagent`. For the final single-stack deployment, stop
   stack `36`, then redeploy/start stack `26`. For the interim workaround,
   restart stack `36` through Portainer and leave stack `26`'s collector
   service disabled until the inline-config revision is deployed.
4. Wait at least 30 seconds (two 15-second scrape intervals) after the
   containers report running before judging the result. Confirm the four
   persistent bind paths `/data/grafana`, `/data/victoriametrics`,
   `/data/loki`, and `/data/vmagent` are still attached.
5. Repeat the health and PromQL checks above, including a range query over at
   least five minutes. In Grafana, open dashboard `beelink-cadvisor`
   (`Beelink Host & Containers`), select host `beelink`, and verify its seven
   panels have current values. The expected current checks are `up = 1`, both
   scrape-error gauges `= 0`, four CPU cores, non-zero memory, and positive
   named container CPU/memory series.

### Restart result (2026-08-24)

The externally supplied Grafana secret was restored and the stopped monitoring
services were brought back without deleting any data directories. Starting the
Git stack from the current `main` ref pulled cAdvisor `v0.55.1`; on this Docker
host that version emitted raw cgroup series without Docker `name` labels, so
three container dashboard queries were empty even though `up = 1`. The
repository configuration therefore pins cAdvisor to the previously verified
`v0.52.1`; after restarting that collector and allowing fresh scrapes, the
checks returned `up = 1`, `machine_scrape_error = 0`,
`container_scrape_error = 0`, `machine_cpu_cores = 4`,
`machine_memory_bytes = 16534200320`, and 13 named container series. All seven
Grafana panel queries returned non-empty current data and the host variable
resolved to `beelink`.

The Grafana datasource and dashboard are persistent runtime state, not
provisioned from this repository. PNG snapshot rendering remains unavailable
unless the Grafana Image Renderer service is installed; this does not prevent
normal in-browser dashboard panels from executing their queries. The final
clean Portainer Git redeploy still requires the inline-config commit to be
merged/pushed to the stack's configured Git ref; the direct cAdvisor rollback
above was a live validation recovery, not a replacement for that documented
redeploy.
