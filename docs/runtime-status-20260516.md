# Runtime Status 2026-05-16 15:25 CST

## Active runtime

- Server: `anbo236` / `172.31.1.236`
- Deploy directory: `/home/jscn123/PycharmProjects/go-collector`
- Active process: `2928885`
- Command:
  - `./bin/collector -config ./configs/runtime.official.json -data-dir ./data-official-20260415-nightb -log-dir ./logs-official-20260415-nightb -log-level info -instance-lock ./run/collector.lock`

The single-instance lock is active and no duplicate formal collector process was observed.

## Current findings

1. The server Git checkout had drifted from GitHub:
   - server `HEAD` was `0f0b617`
   - GitHub/local `origin/main` was `763ca76`
   - runtime hotfix files existed only on the server worktree

2. External ONU staging write was present in the running binary but not in GitHub.
   This status file records that the staging path is now part of the source tree.

3. The remaining database bottleneck is `octets` writes:
   - `olt_octets_last` still had a `1205` lock wait timeout on `2026-05-16 09:45:01`
   - processlist showed concurrent long `olt_octets_his` and `olt_octets_last` statements
   - `olt_collect_round_his` persisted rows lagged several hours behind collection completion

## Code direction

- Keep external ONU bulk writes on the staging-table merge path.
- Isolate external ONU only from local ONU writes, not from `round` or `octets` writes.
- Force `octets` to a single writer path.
- Write `octets` history and latest chunks without one large wrapping transaction, so locks are released per chunk instead of at the end of a large batch.
- Split external ONU staging merge by staging-table primary-key ranges so each `olt_onu_last` merge transaction scans and touches fewer rows.

This is intended to remove the current chain-level hot-table contention rather than only increasing timeouts or lowering collection concurrency.
