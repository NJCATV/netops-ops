# AIOps integration completion audit

Production evidence captured on 2026-07-17.

| Requirement | Production result | Status |
|---|---|---|
| Final placement | 233 frontend/auth/BFF; 20 AIOps API/MySQL/ELK; 236 remains platform DB | Deployed |
| Embedded AIOps pages | `/2026` build and two `app_menus` entries live | Deployed |
| Standalone AI chat | `/ai-assistant`, signed identity and per-user sessions | Deployed; GET acceptance passed |
| Unified login | HMAC identity projection; local AIOps auth disabled on 18080 | Deployed |
| Role enforcement | Three live roles tested; model/audit endpoints fail closed | Passed |
| Device isolation | 565 inventory devices projected; ES and AI queries scoped | Passed |
| Empty scope | Overview returned zero and no latest event | Passed |
| Signature security | Replay, expiry and tamper tests returned 401 | Passed |
| Database migration | Additive v2 migration applied; dry-run after apply returned no statements | Passed |
| Light/dark theme | Shared platform tokens; production assets live; local browser matrix passed | Passed |
| Backup/rollback | Code, config, frontend and compressed MySQL backups checksummed | Passed |
| Scheduler writes | Read-only gate until root container restart loads scoped scheduler | Pending admin restart |
| QQ service identity | Code and secrets staged; root container still runs old process | Pending admin restart |
| 233 NTP | RTC fallback keeps strict signatures valid; system clock still unsynchronized | Pending admin action |

## Verification commands completed

- `pytest tests -q`: 66 passed.
- `npm run build`: Vue TypeScript check and Vite production build passed.
- Python compilation passed locally, in the 20 release, and for the deployed 233 BFF.
- Three-role navigation/BFF checks, AI chat GET, audit authorization, empty-scope, replay, expiry and tamper checks passed.
- `jscn_aiops.sql.gz` passed `gzip -t`; production API and database health are green.

## Remaining privileged cutover

The source, environment and rollback material are already staged. Current SSH users cannot restart root-owned Docker containers or enable NTP. Until those two privileged actions are performed, task mutations intentionally remain disabled; all other embedded AIOps functions are live.
