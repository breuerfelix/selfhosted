# Hetzner single-node K3s handoff

Read [migration-runbook.md](migration-runbook.md) first. It records live migration state, completed actions, backup location, rollback procedure, and next step. Read [architecture.md](architecture.md) for target design and decisions still pending. [ubuntu-updates.md](ubuntu-updates.md) records applied host update schedule. [firewall.md](firewall.md), [k3s-install.md](k3s-install.md), and [flux-bootstrap.md](flux-bootstrap.md) cover installed components and rebuild steps.

As of 2026-10-26, Coolify remains stopped; Ghost/Fathom are backed up and copied into `/srv/k3s-data`; nightly Ubuntu updates are configured. K3s `v1.36.5+k3s1` is **running and enabled**, with node and bundled system deployments Ready. Mac can access Kubernetes API directly using ignored `temp/hetzner-kubeconfig`. Flux v2.9.6 is installed and reconciling this public Git repository over HTTPS. Application and PV manifests are not installed. Public applications remain offline by agreement.

Work one stage at a time with user. Before each consequential server change, state exact action and expected result; stop at checkpoint afterward. Do not run whole migration unattended.
