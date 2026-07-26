# Worklog 2026-06-04 Collector and Database Optimization

## Scope

This record documents the production work done on 2026-06-04 for the Go
collector runtime on `anbo236`:

- pulled and deployed the latest collector code
- enabled the new summary and traffic-rate paths
- cleaned non-production historical data
- rebuilt high-write database tables to release space
- added time partitioning to history and summary tables
- filtered stale external-source data older than one year before it reaches
  `last` or `his` tables

The collector historical data is not treated as production-retained data yet, so
history tables were allowed to be cleared and rebuilt.

## Runtime State After Maintenance

Server:

- host: `anbo236`
- deploy directory: `/home/jscn123/PycharmProjects/go-collector`
- runtime command:
  - `./bin/collector -config ./configs/runtime.official.json -data-dir ./data-official-20260415-nightb -log-dir ./logs-official-20260415-nightb -log-level info -instance-lock ./run/collector.lock`

Collector process after the last maintenance window:

- single formal collector process was restarted successfully
- instance lock is active
- `summary`, OLT local, OLT external, OLT performance, CMTS local, and CMTS
  external tasks start from the same official runtime

Known external-source issue still present:

- `wangguan_qixia` still fails to connect:
  - `dial tcp 172.30.100.3:3306: i/o timeout`

## Code Changes Deployed

### External ONU stale-data filter

`internal/scheduler/external_onu_task.go` now filters external ONU rows before
the bulk write path.

Behavior:

- external rows with `query_time < now - 1 year` are dropped
- dropped rows do not enter `olt_onu_his`
- dropped rows do not update `olt_onu_last`
- source task detail JSON now includes:
  - `fetched`
  - `accepted`
  - `stale_rows`

Observed first-run filter counts:

| source | fetched | accepted | stale_rows |
| --- | ---: | ---: | ---: |
| `wangguan_nanjing` | 299,284 | 208,396 | 90,888 |
| `wangguan_gaochun` | 35,693 | 31,011 | 4,682 |
| `wangguan_jiangning` | 12,665 | 12,665 | 0 |

### External CMTS stale-data filter

`internal/scheduler/cmts_external_task.go` now filters external CMTS rows before
grouping and sink writes.

Behavior:

- external CMTS records with `query_time < now - 1 year` are dropped
- dropped rows do not enter `cmts_cm_his`
- dropped rows do not update `cmts_cm_last`
- source task detail JSON now includes:
  - `fetched`
  - `accepted`
  - `stale_rows`

Observed first-run filter counts:

| source | fetched | accepted | stale_rows |
| --- | ---: | ---: | ---: |
| `wangguan_nanjing_cm` | 40,286 | 40,286 | 0 |

## Database Work Done

### Schema and table maintenance

Before rebuilding tables, a schema-only backup was written on the server:

- `/home/jscn123/PycharmProjects/go-collector/db-maint-20260604233230/schema-before-rebuild.sql`

The following high-write or generated tables were rebuilt using an empty-table
swap pattern:

1. `CREATE TABLE new LIKE old`
2. `RENAME TABLE old TO old_backup, new TO old`
3. `DROP TABLE old_backup`

This released old InnoDB table space and reset non-production history.

Tables rebuilt:

| group | tables |
| --- | --- |
| OLT raw history | `olt_onu_his`, `olt_octets_his`, `olt_if_rate_his` |
| OLT latest generated state | `olt_onu_last`, `olt_octets_last`, `olt_perf_device_metric_last`, `olt_perf_board_metric_last` |
| OLT summaries | `olt_onu_power_hourly`, `olt_onu_power_daily`, `olt_if_rate_hourly`, `olt_if_rate_daily` |
| OLT performance history and summaries | `olt_perf_device_metric_his`, `olt_perf_board_metric_his`, `olt_perf_device_metric_hourly`, `olt_perf_device_metric_daily`, `olt_perf_board_metric_hourly`, `olt_perf_board_metric_daily` |
| CMTS raw and latest | `cmts_cm_his`, `cmts_cm_last`, `cmts_performance_his` |
| CMTS summaries | `cmts_cm_metric_hourly`, `cmts_cm_metric_daily` |
| audit/stage generated tables | `olt_collect_round_his`, `cmts_collect_round_his`, `olt_onu_quality_event`, `olt_onu_external_stage` |

Deprecated or stale large tables dropped:

- `cmts_cm_last_bak_20260428`
- `olt_performance_his_deprecated_20260527`
- `olt_performance_last_deprecated_20260527`

### Partitioning added or normalized

Time-series tables were partitioned by their time column. Current partition set
covers monthly ranges from `2025-06` through `2027-12`, plus `pmax`.

| table | partition column | partition count |
| --- | --- | ---: |
| `olt_onu_his` | `query_time` | 32 |
| `olt_octets_his` | `query_time` | 32 |
| `olt_if_rate_his` | `query_time` | 32 |
| `cmts_cm_his` | `query_time` | 32 |
| `olt_perf_device_metric_his` | `query_time` | 32 |
| `olt_perf_board_metric_his` | `query_time` | 32 |
| `olt_onu_power_hourly` | `stat_time` | 32 |
| `olt_onu_power_daily` | `stat_date` | 32 |
| `cmts_cm_metric_hourly` | `stat_time` | 32 |
| `cmts_cm_metric_daily` | `stat_date` | 32 |
| `olt_if_rate_hourly` | `stat_time` | 32 |
| `olt_if_rate_daily` | `stat_date` | 32 |
| `olt_perf_device_metric_hourly` | `stat_time` | 32 |
| `olt_perf_device_metric_daily` | `stat_date` | 32 |
| `olt_perf_board_metric_hourly` | `stat_time` | 32 |
| `olt_perf_board_metric_daily` | `stat_date` | 32 |

After rebuilding and analyzing, the previously multi-GB tables were reduced to
small empty table structures. New data then began entering the rebuilt tables
normally.

## Current Data Flow and Durations Observed

Observed after the one-year external stale filter was deployed:

| flow | observed duration | notes |
| --- | ---: | --- |
| CMTS external sync | about 3 seconds | source fetch and task write finished quickly |
| OLT performance collection | about 3 minutes | 485 targets; some devices still fail due to model/OID/device reachability |
| ONU external source fetch | 1-6 seconds per source | write phase is the expensive part |
| ONU external write | can take minutes | bulk writes to `olt_onu_his` and `olt_onu_last`; reduced by stale filtering |
| summary rollup | can be slow for ONU power | previous `olt_onu_power_hourly` query ran for 10+ minutes before being killed during maintenance |

## Cleaning and Retention Logic

Current code still uses `DELETE ... LIMIT 50000` in `internal/summary/cleanup.go`
for retention cleanup.

Configured retention logic in code:

| data | current cleanup rule |
| --- | --- |
| `olt_onu_his` | delete rows older than 7 days |
| `cmts_cm_his` | delete rows older than 7 days |
| `olt_octets_his` | delete rows older than 7 days |
| `olt_if_rate_his` | delete rows older than 7 days |
| `olt_perf_device_metric_his` | delete rows older than 30 days |
| `olt_perf_board_metric_his` | delete rows older than 30 days |
| hourly summaries | delete rows older than 12 months |
| daily summaries | delete rows older than 2 years |

Important follow-up:

- because the main time-series tables are now partitioned, cleanup should be
  changed from large deletes to partition maintenance:
  - drop whole old partitions when possible
  - only use small chunk deletes for current-period leftovers

## Issues Found During Maintenance

### Summary rollup can block the database

`summary_rollup` ran a long `INSERT INTO olt_onu_power_hourly ... SELECT ...`
for more than 10 minutes. Killing the query left MySQL in `query end` for a
while, which blocked other maintenance until the server finished cleanup.

Recommended fixes:

- do not roll up the current incomplete hour
- split ONU power rollup by source, region, or device-id ranges
- make each rollup unit commit independently
- consider reducing `lookback_hours` after initial stabilization

### Retention cleanup should become partition-aware

Now that time-series tables are partitioned, old-data cleanup should not rely on
large `DELETE` statements.

Recommended fixes:

- implement monthly partition lifecycle management in code or an operations SQL
  script
- pre-create future partitions before the month changes
- drop partitions older than the retention window

### External write path is still large

External ONU sync can still write hundreds of thousands of rows per run, even
after stale filtering.

Recommended fixes:

- write `last` for accepted current rows
- write `his` only for rows in a short rolling window or changed rows
- consider per-source write batches with smaller transactions and better
  progress metrics

### Server hotfix drift risk

The server currently has these code changes deployed. They must stay committed
to GitHub so the deployed runtime does not drift from source control again.

## Worth Doing Next

1. Commit and push the one-year external stale-data filter.
2. Add a partition-maintenance SQL or Go task that drops old partitions instead
   of deleting old rows.
3. Rewrite summary rollup to process smaller independent chunks.
4. Add dashboard queries for:
   - task duration
   - rows fetched / accepted / stale
   - write latency by task
   - summary lag
   - partition coverage
5. Investigate non-network collection failures:
   - CMTS `empty_result`
   - OLT performance unsupported OIDs or models
   - external ONU invalid MAC and bad-row counts
6. Fix or disable the failing `wangguan_qixia` external source until network
   access is restored.
