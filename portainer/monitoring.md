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
