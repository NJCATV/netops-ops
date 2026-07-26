# Server naming migration matrix

This is the current migration target. Repository names are also the canonical deployment directory names below `/srv/netops/`.

| Server | Current confirmed runtime | Target repository / directory | Target service or runtime | Status |
| --- | --- | --- | --- | --- |
| 233 platform | `anbo_wx`, `zhiwei-api.service`, Nginx `:5772` | `netops-littleProgram`, `netops-platform-api`, `netops-portal-web` | `netops-platform-api.service`, Nginx `/api/*` | Sources and static artifact staged; root cutover pending |
| 236 collection | `go-collector` source plus `newalert.service` / `newalertapi.service` | `netops-collector` | `netops-collector.service`; alert runtime ownership must be confirmed before rename | Inventory complete; live collector unit not yet identified |
| 20 AIOps | Compose files at `/opt/jscn-aiops/deploy` | `netops-aiops` | `netops-aiops-*` Compose project/container names | Compose path confirmed; Docker inspection needs elevated access |
| 213 RADIUS | RADIUS monitor runtime | `netops-radius-monitor` | `netops-radius-monitor.service` | SSH access required |
| 212 data | ClickHouse runtime | operational data node, no application-code repository | `clickhouse-server` retained | SSH access required |

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
