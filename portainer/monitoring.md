# Monitoring stack

`monitoring.yaml` runs Grafana, VictoriaMetrics, Loki, and the Beelink host collector.
The collector path is:

```text
cAdvisor -> vmagent -> VictoriaMetrics <- Grafana
```

## Deployment inputs

The Portainer stack uses the Git repository's `portainer/monitoring.yaml` file. The
scrape configuration is versioned next to it at
`portainer/vmagent/prometheus.yml` and is loaded through the Compose `configs`
entry; no host-side configuration file is required.

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

## Grafana dashboard

The provisioned dashboard is versioned at
`portainer/grafana/dashboards/beelink-cadvisor.json`. Grafana loads it through
`portainer/grafana/provisioning/dashboards/beelink.yml` into the `Beelink` folder.
The files are mounted with Compose configs, so a Portainer stack redeploy updates
the dashboard without requiring a manual import. Dashboard panels intentionally
omit a datasource UID, which makes Grafana use its configured default rather than
hard-coding a datasource name or UID. The existing default is the healthy
VictoriaMetrics Prometheus datasource. Select `beelink` in the visible Host
variable (it is the default returned by the `machine_memory_bytes` series query).

The dashboard covers cAdvisor's available CPU, memory, filesystem, network, and
container CPU-load metrics. Host CPU and working-set memory are derived from the
cAdvisor root cgroup (`id="/"`). cAdvisor does not expose host uptime or a host
load-average metric, so those views are intentionally not fabricated; add a
node-exporter collector if host uptime/load is required.

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
5. Redeploy or restart the stack and repeat the checks; `/data/victoriametrics`
   and `/data/vmagent` must remain intact.
6. In Grafana, open the `Beelink Host & Containers` dashboard in the `Beelink`
   folder, confirm panels use the existing VictoriaMetrics default datasource, and
   confirm the Host variable resolves to `beelink`.
