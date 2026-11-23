# Beelink Radar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Run a read-only Radar trial on Beelink over private Tailscale HTTPS.

**Architecture:** Add the upstream chart as an application HelmRelease under the existing Flux apps tree. Use a separate Tailscale Ingress matching existing applications, without persistent storage or Cloud.

**Tech Stack:** Kubernetes, Flux, Helm, Kustomize, Tailscale operator.

**Spec:** `docs/superpowers/specs/2026-11-23-beelink-radar-design.md`

## Steps

- [x] Add and validate the pinned Radar application and documentation.
- [x] Review, commit and push for Flux deployment, verify private HTTPS and read-only access, and notify the user.

## Global Constraints

One replica, namespace `radar`, Tailscale hostname `radar.vulture-skink.ts.net`; no public or LAN endpoint, Cloud, general Secret permissions, writes, exec, persistence, backups, or scheduling constraints. MCP must be read-only. Preserve unrelated files and cluster resources.

## Review Focus

- The chart must not introduce cluster write, impersonation, general Secret-read, or exec permissions.
- The ingress must use Tailscale without Funnel; Services must remain ClusterIP.
- Radar's hostname guard must accept the full tailnet hostname without a wildcard.
- In-memory operation must work with the chart's read-only root filesystem.
- Flux must adopt the deployment from the pushed commit; no direct installation.

### Task 1: Application manifests and local verification

**Files:** Create `beelink/cluster/apps/radar/{namespace,kustomization,release,ingress}.yaml`; modify `beelink/cluster/apps/kustomization.yaml`, `beelink/README.md`, and the Flux manager patterns in `renovate.json`.

**Interfaces:** Consume the existing Flux Helm controller and Tailscale ingress class; produce HelmRelease `radar` and ClusterIP Service `radar` in namespace `radar`.

Verify the published chart version. Set `allowedHosts` to the full tailnet hostname, `disableExec: true`, `extraArgs: [--mcp-read-only]`, and `usageReporting.enabled: false`; retain default read-only RBAC and memory timeline. Render the chart with the exact HelmRelease values and assert the five review conditions. Run `kubectl kustomize beelink/cluster/apps`, `helm lint`, and server-side dry runs against Beelink. Update the README with the access URL, read-only limitations, and ephemeral history.

### Task 2: Trial rollout and live verification

**Files:** No additional application files expected.

**Interfaces:** Consume Task 1 resources; produce a Ready deployment and private HTTPS URL.

Request an independent review after successful validation, fix important findings, and commit and push only this change to `main`, as the user requested. Reconcile the existing Flux apps Kustomization and wait for Helm reconciliation and deployment readiness. Inspect Service types, ingress class and annotations, and Tailscale proxy status. Use `kubectl auth can-i` as Radar's ServiceAccount to confirm ordinary reads/logs are allowed and writes/Secrets/exec/impersonation are denied. Verify HTTPS and the read-only MCP capability. Rebuild both Beelink Kustomizations and inspect the final diff. Confirm Flux reports the pushed revision, then notify the user with the access URL.
