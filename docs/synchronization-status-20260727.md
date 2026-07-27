# NetOps source synchronization status — 2026-07-27

This document distinguishes a **controlled source copy** from a **production runtime**. A matching controlled copy is safe to audit and release; it does not authorize replacing a running directory that contains unreviewed work.

## Canonical GitHub repositories

| Module | Repository | Canonical source |
| --- | --- | --- |
| Operations, deployment, topology and security | `NJCATV/netops-ops` | current protected `main` |
| Collector | `NJCATV/netops-collector` | current protected `main` |
| Portal web | `NJCATV/netops-portal-web` | current protected `main` |
| Platform API | `NJCATV/netops-platform-api` | current protected `main` |
| RADIUS monitor | `NJCATV/netops-radius-monitor` | current protected `main` |
| AIOps | `NJCATV/netops-aiops` | current protected `main` |
| Mini program | `NJCATV/netops-littleProgram` | current protected `main` |

All seven local canonical clones under `F:/codeXSpace/netops-migration/` were clean at this audit. Runtime secrets, captures, database exports and logs are intentionally excluded from Git.

## Server alignment

| Host | Controlled staging copy | Production runtime | Release state |
| --- | --- | --- | --- |
| 233 platform | `netops-ops` tracks current `main` | API source remains `b792f2f`; web source remains `13ae970` | Do not overwrite: the user is actively adjusting portal code. API/web changes need a reviewed release, build and health check. |
| 236 collector | `netops-collector` verified at `ca94c88`, clean | Legacy collector remains at `/home/jscn123/PycharmProjects/go-collector` at `e6c7c51`, clean | Source baseline is preserved; directory/service rename requires the collector release plan and source-allowlist decision. |
| 20 AIOps | `netops-aiops` fast-forwarded to `b9ce25c` | `/opt/jscn-aiops` is an old dirty Git worktree | Preserved intentionally. Its remaining semantic changes must be reviewed and merged before runtime cutover. |
| 213 RADIUS | `netops-radius-monitor` verified at `6eab281` | `/opt/radius_monitor` is a non-Git runtime directory | Captured source is controlled; a dedicated release window is required to rename its unit/directory. |
| 212 data | `netops-ops` tracks current `main` through a verified offline bundle, clean | ClickHouse only; no application source tree | Guard and Fail2ban are active. No fabricated application repository is needed for this data node. |

## Local legacy workspace quarantine

`F:/codeXSpace/newGoColletor` is a historical monorepo, not a deployment source. It contains user-owned, uncommitted API and portal edits plus a small AIOps hotfix folder. The AIOps hotfix was reviewed, syntax-checked and integrated into `netops-aiops` as `b9ce25c`.

The remaining portal/API edits must not be deleted or copied wholesale: the portal is currently under active user adjustment, and the legacy monorepo has a different repository boundary. Before removing this workspace, create reviewed commits in `netops-portal-web` and `netops-platform-api`, then run their build/test gates and deploy through the matching release plan.

## Synchronization rule

1. Commit a reviewed module change only in its canonical repository.
2. Fast-forward the matching `netops-staging/<module>` clone when the host can reach GitHub or from a verified offline bundle.
3. Compare staging with the running directory, excluding runtime-only configuration.
4. Switch service/Nginx/Compose only in a release window with health check and rollback point.
5. Record the commit and validation result here or in the module release note.
