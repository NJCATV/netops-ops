# Backend API Data Contract

Date: 2026-07-01

This document defines the first backend/API read contract for the collector data layer. The collector remains a long-running data writer, not a Web service.

## Storage Split

| Use case | Read from | Object |
|---|---|---|
| ONU current lookup by MAC | MySQL | `v_onu_current` |
| Collector task health | MySQL | `collector_task_overview`, `collector_task_detail` |
| OLT/CMTS inventory and OID metadata | MySQL | `olt_devices`, `cmts_devices`, `cmts_oids` |
| ONU optical trend | ClickHouse | `go_collector_ch.onu_optical_sample` |
| Daily bad ONU export | ClickHouse | `go_collector_ch.onu_quality_daily_detail` |
| Daily ONU traffic | ClickHouse | `go_collector_ch.onu_traffic_daily` |
| OLT performance trend | ClickHouse | `go_collector_ch.olt_perf_sample` |
| AIOps anomaly candidates | ClickHouse | `go_collector_ch.analysis_event_candidate` |

MySQL should not be used for long-term raw history. ClickHouse owns history and analytics.

## Endpoint Draft

### `GET /api/onu/{mac}/current`

Purpose: find the current upstream OLT/PON/ONU position and optical state for one ONU MAC.

Source: MySQL `v_onu_current`.

Rules:
- Normalize the path MAC before querying.
- Return at most one row.
- Use the deduplicated view, not `olt_onu_last` directly.

Core fields:
- `onu_mac`
- `olt_device_id`
- `olt_name`
- `region`
- `pon_port`
- `if_index`
- `rx_power`
- `tx_power`
- `status`
- `quality_bad`
- `quality_code`
- `quality_rule_version`
- `query_time`

### `GET /api/onu/{mac}/power-trend?range=12h|24h|7d|15d`

Purpose: return optical power trend data.

Source: ClickHouse `onu_optical_sample`.

Rules:
- Normalize MAC before querying.
- Allowed ranges are `12h`, `24h`, `7d`, `15d`.
- Reject ranges longer than 15 days unless the retention policy changes.
- Sort by `sample_time ASC`.

Core filters:
- `onu_mac = normalized_mac`
- `sample_time >= now() - selected_range`

Core fields:
- `sample_time`
- `source_type`
- `region`
- `olt_device_id`
- `olt_name`
- `pon_port`
- `if_index`
- `rx_power`
- `tx_power`
- `status`
- `quality_code`

### `GET /api/quality/onu-daily?date=YYYY-MM-DD`

Purpose: daily bad ONU list for query and export.

Source: ClickHouse `onu_quality_daily_detail`.

Filters:
- `stat_date`
- optional `region`
- optional `olt_device_id`
- optional `pon_port`
- optional `quality_type`

Core fields:
- `stat_date`
- `region`
- `olt_device_id`
- `olt_name`
- `pon_port`
- `if_index`
- `onu_mac`
- `rx_power`
- `tx_power`
- `status`
- `quality_type`
- `quality_reason`
- `source_type`
- `last_query_time`

### `GET /api/onu/{mac}/traffic-daily?from=YYYY-MM-DD&to=YYYY-MM-DD`

Purpose: daily traffic result for one ONU.

Source: ClickHouse `onu_traffic_daily`.

Rules:
- Normalize MAC before querying.
- Default window should be recent 30 days.

Core fields:
- `stat_date`
- `region`
- `olt_device_id`
- `pon_port`
- `if_index`
- `onu_mac`
- `in_bytes`
- `out_bytes`
- `total_bytes`
- `quality_code`

### `GET /api/olt/{id}/performance?range=12h|24h|7d|15d`

Purpose: OLT CPU/memory/board performance trend.

Source: ClickHouse `olt_perf_sample`.

Filters:
- `olt_device_id`
- optional `metric_scope`
- optional `metric_key`
- selected time range

Core fields:
- `sample_time`
- `region`
- `olt_device_id`
- `olt_name`
- `metric_scope`
- `slot_id`
- `board_name`
- `metric_key`
- `metric_value`
- `quality_code`

### `GET /api/analysis/candidates?date=YYYY-MM-DD`

Purpose: provide basic anomaly candidates to AIOps.

Source: ClickHouse `analysis_event_candidate`.

Filters:
- `event_date`
- optional `event_type`
- optional `severity`
- optional `region`
- optional `olt_device_id`
- optional `pon_port`

Current event types:
- `pon_weak_light_batch`
- `onu_rx_degradation`
- `olt_perf_threshold`

Core fields:
- `event_date`
- `event_time`
- `event_type`
- `severity`
- `region`
- `olt_device_id`
- `olt_name`
- `pon_port`
- `if_index`
- `onu_mac`
- `metric_key`
- `metric_value`
- `baseline_value`
- `delta_value`
- `affected_count`
- `total_count`
- `affected_rate`
- `rule_code`
- `evidence`

### `GET /api/collector/tasks`

Purpose: show collector health and recent task state.

Source: MySQL `collector_task_overview`, `collector_task_detail`.

Rules:
- `collector_task_overview` is the task-level view.
- `collector_task_detail` is for per-source or current-round details.
- A task can be healthy even when `status=running`, if counters and log progress continue.
- `onu_external` intentionally waits `sources.startup_delay_sec` after collector restart before the first sync.

## Page Configuration Candidates

The following runtime config values should be moved to a page-configurable table or service later:

| Config path | Purpose |
|---|---|
| `quality.onu_rx_low_dbm` | ONU low optical threshold |
| `quality.onu_rx_high_dbm` | ONU high optical threshold |
| `quality.onu_rx_invalid_min_dbm` | invalid lower optical bound |
| `quality.onu_rx_invalid_max_dbm` | invalid upper optical bound |
| `quality.pon_event_bad_rate_major` | PON weak-light major rate |
| `quality.pon_event_bad_rate_critical` | PON weak-light critical rate |
| `quality.pon_event_bad_min_major` | PON weak-light major count |
| `quality.pon_event_bad_min_critical` | PON weak-light critical count |
| `quality.onu_degradation_drop_db` | ONU degradation major drop |
| `quality.onu_degradation_high_drop_db` | ONU degradation critical drop |
| `quality.olt_cpu_usage_major` | OLT CPU major threshold |
| `quality.olt_cpu_usage_critical` | OLT CPU critical threshold |
| `quality.olt_mem_usage_major` | OLT memory major threshold |
| `quality.olt_mem_usage_critical` | OLT memory critical threshold |
| `gather.rule_value` | local OLT collection interval in minutes |
| `sources.sync_interval_sec` | external ONU sync interval |
| `performance.interval_sec` | OLT performance collection interval |
| `summary.daily_run_hour` / `summary.daily_run_minute` | daily summary run window |

## Current Non-Goals

- The collector should not become the backend API server.
- The backend should not scan old MySQL history tables.
- AIOps root-cause reasoning remains outside the collector; the collector only provides candidates and evidence.
