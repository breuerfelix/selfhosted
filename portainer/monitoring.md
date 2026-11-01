# Retired Docker monitoring

Grafana, Loki, and VictoriaMetrics run in Beelink K3s. Their original Docker
containers remain stopped with restart policy `no` for coordinated rollback.
Do not start them while Kubernetes owns `/data/grafana`, `/data/loki`, or
`/data/victoriametrics`.

On 1 November 2026, the user retired Docker cAdvisor and vmagent completely.
Their containers, cached named images, and Compose/config definitions were
removed. They were not migrated to Kubernetes. Container/host telemetry panels
may show only historical data; no replacement collector was installed.

`monitoring.yaml` retains only backend rollback definitions. Portainer itself
is stopped with restart policy `no`. Do not redeploy stack 26 or re-enable
Portainer automation without reviewing active Kubernetes ownership first.
Screeps collectors run separately in K3s and write to internal monitoring
Services.

See [current applications](../beelink/README.md) and
[monitoring and Screeps operations](../beelink/docs/maintenance.md#monitoring-and-screeps).
