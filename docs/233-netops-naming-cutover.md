# 233 NetOps naming and path cutover

## Confirmed post-cutover state

The cutover completed on 2026-07-26. The active public listener is
`172.31.1.233:5772` (TLS); Nginx forwards the NetOps API to the loopback-only
`127.0.0.1:7001` BFF.

| Item | Verified state |
| --- | --- |
| Application source | `/srv/netops/netops-littleProgram` |
| BFF adapter source | `/srv/netops/netops-platform-api` |
| Portal static assets | `/srv/netops/netops-portal-web/dist` |
| systemd unit | `netops-platform-api.service` (`active`, `enabled`) |
| Public API | `/api/netops2026/*` |
| Legacy `/wx/*` route | Explicit `410 Gone` rejection |
| Old `zhiwei-api.service` | Stopped after successful verification |

The historical `anbo_wx` source and `zhiwei-api.service` are retained only as
rollback material until a separately approved cleanup change. They are not the
active deployment identity.

## Target naming

| Concern | Current legacy name | Target name |
| --- | --- | --- |
| Platform host source | `anbo_wx` | `/srv/netops/netops-littleProgram` |
| BFF integration source | mixed into host working tree | `/srv/netops/netops-platform-api` |
| Portal source/build | historical deployment directory | `/srv/netops/netops-portal-web` |
| systemd unit | `zhiwei-api.service` | `netops-platform-api.service` |
| Service description | 智维平台 API | NetOps Platform API |
| Primary API prefix | historical `/wx/api/netops2026/` | `/api/netops2026/` |
| Obsolete API prefix | `/wx/api/netops2026/` | removed at cutover |

The external HTTPS entry remains `:5772`. Ports `80` and `443` must not appear as the NetOps entry in topology cards or documentation.

## Executed cutover and repeatable procedure

1. Sync the three pinned GitHub modules under `/srv/netops/`; copy no `.env`, logs, uploads, database files, keys, or historical backups into Git.
2. Create `/etc/netops/netops-littleProgram.env` with mode `0640`, owner `root:www-data`; migrate values from the old protected environment file manually.
3. Preserve the protected virtual environment in `/srv/netops/netops-littleProgram/backend` and apply the NetOps adapter from `netops-platform-api/platform-adapter/host-application/`.
4. Build `netops-portal-web` to `/srv/netops/netops-portal-web/dist` and point the Nginx SPA root to that directory.
5. Install the unit and Nginx examples in `deploy/233/`; run `nginx -t` and `systemctl daemon-reload` before restart.
6. Verify with TLS SNI: `curl --resolve anbo.njcatv.net:5772:127.0.0.1 https://anbo.njcatv.net:5772/api/netops2026/auth/me` must return `401`; the equivalent `/wx/api/health` request must return `410`. Roll back by restoring the prior unit and Nginx backup only if verification fails.
7. After a stable observation window, remove the old unit and legacy source directory only through an approved maintenance change. Do not delete them during initial cutover.

## Security boundaries

- `5772/tcp` is the browser ingress; the BFF on `7001/tcp` remains loopback-only.
- Nginx is the only component that can reach the BFF from browser traffic.
- Database and downstream service permissions remain governed by the per-server firewall and database rules documented in `server-topology.md` and `deploy/security/`.
- fail2ban protects SSH on the hardened nodes; it is not a substitute for explicit inbound port allowlists.
