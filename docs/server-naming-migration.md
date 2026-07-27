# Server naming migration matrix

This is the current migration target. Repository names are also the canonical deployment directory names below `/srv/netops/`.

| Server | Current confirmed runtime | Target repository / directory | Target service or runtime | Status |
| --- | --- | --- | --- | --- |
| 233 platform | Historical `anbo_wx`, `zhiwei-api.service` | `netops-littleProgram`, `netops-platform-api`, `netops-portal-web` | `netops-platform-api.service`, Nginx `/api/netops2026/*` | Completed 2026-07-26; `/srv/netops/` sources active, legacy `/wx/*` returns 410 |
| 236 collection | `go-collector` process at `/home/jscn123/PycharmProjects/go-collector` plus independent `newalert.service` / `newalertapi.service` | `netops-collector` | `netops-collector.service`; alert runtime ownership must be confirmed before rename | Source baseline verified and staging clone created; live process/directory cutover still requires a release plan |
| 20 AIOps | Compose files at `/opt/jscn-aiops/deploy` | `netops-aiops` | `netops-aiops-*` Compose project/container names | Source synchronized to a controlled staging clone; runtime and port guard verified; deployment-directory/container rename remains a separate planned change |
| 213 RADIUS | `radius-sniffer.service` at `/opt/radius_monitor` | `netops-radius-monitor` | `netops-radius-monitor.service` | Source synchronized to a controlled staging clone; SSH and port guard verified; source/unit canonical-name cutover still needs a dedicated release window |
| 212 data | ClickHouse runtime | operational data node, no application-code repository | `clickhouse-server` retained | Completed 2026-07-27: controlled `netops-ops` staging copy, ClickHouse port guard, and SSH Fail2ban verified; no application-name cutover applies |

## Naming rules

- No active application code, service unit, deployment directory or Nginx API route may use `wx`, `anbo_wx`, `zhiwei`, `newalert`, or a date/version path as its primary NetOps name.
- Historical database/schema names may remain until a dedicated database migration is approved; they are not used as public URLs or service identities.
- Browser entry is `https://anbo.njcatv.net:5772/`; NetOps API is `/api/netops2026/*`. Port `7001` remains loopback-only.
- Legacy names may appear only in immutable migration history, backups, or rollback paths.

## Verification gate per server

1. The deployed Git revision equals the repository `main` revision recorded in the release log.
2. The systemd or Compose runtime uses the canonical module name and canonical directory.
3. No legacy public API route responds successfully.
4. Firewall rules, database allowlists and fail2ban configuration remain unchanged or are explicitly revalidated after the rename.
