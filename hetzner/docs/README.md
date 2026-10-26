# Hetzner single-node K3s handoff

Read [migration-runbook.md](migration-runbook.md) first. It records live migration state, completed actions, backup location, rollback procedure, and next step. Read [architecture.md](architecture.md) for target design and decisions still pending. [ubuntu-updates.md](ubuntu-updates.md) records applied host update schedule. [firewall.md](firewall.md), [k3s-install.md](k3s-install.md), [flux-bootstrap.md](flux-bootstrap.md), [storage.md](storage.md), [secrets.md](secrets.md), and [app-preparation.md](app-preparation.md) cover installed components and rebuild steps.

As of 2026-10-26, Coolify remains stopped; Ghost/Fathom were backed up to this Mac and copied into `/srv/k3s-data`; nightly Ubuntu updates are configured. K3s `v1.36.5+k3s1` is **running and enabled**. Mac can access Kubernetes API using ignored `temp/hetzner-kubeconfig`. Flux v2.9.6 is reconciling this public Git repository over HTTPS. Ghost/Fathom PVs/PVCs are Bound. Ghost, Fathom, redirect, and Noobgallery run internally at one replica each; Screeps remains prepared but inactive. No public ingress exists; public applications remain offline by agreement.

Work one stage at a time with user. Before each consequential server change, state exact action and expected result; stop at checkpoint afterward. Do not run whole migration unattended.
