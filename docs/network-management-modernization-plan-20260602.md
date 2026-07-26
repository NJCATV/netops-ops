# Network Management Modernization Plan

Updated: `2026-06-02 CST`

## 1. Goal

Build the collector into a clear network-management data platform:

- MySQL remains the operational database for inventory, latest state, task state,
  short raw history, and summaries.
- High-volume raw rows are not retained indefinitely.
- Every collector task has measurable output and an acceptance target.
- Frontend pages read `last` and summary tables by default, not raw history.
- Logs and packet/RADIUS analysis can later use ELK/Kafka/Redpanda style
  pipelines without forcing SNMP history into the same storage model.

## 2. Current Task Lines

| Task | Current frequency | Source | Current role |
| --- | ---: | --- | --- |
| `onu_local` | 60 min | OLT SNMP | Local ONU MAC, optical power, IF octets |
| `onu_external` | 60 min | external MySQL + HTTP | External ONU optical power sync |
| `olt_performance` | 60 min | OLT SNMP | OLT and board CPU/memory |
| `cmts_local` | 60 min | CMTS SNMP | Local CM MAC, SNR, level |
| `cmts_external` | 60 min | external Oracle | External CMTS CM/SNR/level sync |

Recent production observations:

- `olt_performance` finishes about 485 devices in about 45 seconds and can move
  to a 5 minute interval.
- `onu_local` is slower and more variable. It includes fallback devices when an
  external ONU source degrades.
- `cmts_local` currently has poor device success, while `cmts_external` is the
  effective CMTS data source.
- The largest database pressure comes from raw history:
  `olt_octets_his`, `olt_onu_his`, `olt_perf_if_metric_his`, and `cmts_cm_his`.

## 3. Data Classes

| Data class | Final source of truth | Frontend use | Long-term value |
| --- | --- | --- | --- |
| Device inventory | `olt_devices`, `cmts_devices`, interface/profile tables | navigation, filters, mapping | permanent |
| ONU latest state | `olt_onu_last` | ONU query, current optical power | permanent latest only |
| ONU optical trend | daily/hourly summary | fault replay, weak optical trend | high |
| OLT traffic rate | rate and rollup tables | MRTG-like charts, uplink/PON trend | high for uplink/PON |
| OLT CPU/memory | `olt_perf_*_metric_last/his` + summary | device/board health | high |
| CMTS latest state | `cmts_cm_last` | CM query, current SNR/level | permanent latest only |
| CMTS trend | daily/hourly summary | fault replay, weak SNR/level trend | medium |
| Collector health | `collector_task_*`, round history | success rate, failed devices, lag | high |
| Packet/RADIUS analysis | ELK + future event pipeline | session/event search, abnormal behavior | high but separate from SNMP history |

## 4. Core Design Decisions

### 4.1 Filter Invalid MACs Before Storage

Invalid MAC rows must not enter `last` or raw history tables.

Applies to:

- `olt_onu_his`
- `olt_onu_last`
- `cmts_cm_his`
- `cmts_cm_last`
- external ONU sync
- external CMTS sync

Invalid means:

- empty string
- all zero MAC
- non-normalizable MAC

Collector task counters should still expose:

- raw source rows
- invalid/zero MAC rows
- valid rows
- rows with valid measurements

This keeps operational visibility without storing useless placeholder rows.

### 4.2 Split Latest, Raw, and Summary

Use this rule for all high-volume metrics:

| Layer | Purpose | Query path | Retention |
| --- | --- | --- | ---: |
| `last` | current state | frontend default | permanent |
| raw history | recent troubleshooting | drill-down only | 7 to 30 days |
| hourly summary | medium-term trends | charts | 12 months |
| daily summary | long-term trends | charts/reports | 2 years |

### 4.3 Avoid Full-Table Deletes

Cleanup must use this order:

1. Stop writing bad/new redundant rows.
2. Create summary tables.
3. Backfill summaries.
4. Verify summary row counts and frontend/API behavior.
5. Drop old partitions when possible.
6. Use chunk delete only for partial current-month cleanup.

No large `DELETE FROM big_table WHERE ...` should run during production hours.

## 5. Target Frequency

| Data | Target frequency | Reason |
| --- | ---: | --- |
| ONU local MAC/power | 60 min initially | current task is heavy; optimize filtering before increasing |
| ONU external sync | 60 min | external source freshness is hourly and one source is degraded |
| OLT device CPU/memory | 5 min | current 45s task cost is acceptable |
| OLT board CPU/memory | 5 min | board fault visibility needs better granularity |
| OLT uplink traffic | 5 min | matches MRTG-style trend expectations |
| OLT PON traffic | 5 min | useful for PON congestion and drop detection |
| OLT ONU traffic | 15 to 60 min or last-only | high volume and lower long-term value |
| CMTS external sync | 60 min | current effective source |
| CMTS local SNMP | 60 min until device fixes | low success rate; do not increase yet |
| Collector task health | continuous per round | operational visibility |

## 6. Storage Plan

### 6.1 ONU Optical Power

| Table | Role | Retention |
| --- | --- | ---: |
| `olt_onu_last` | latest valid ONU state | permanent |
| `olt_onu_his` | valid raw samples | 7 days |
| `olt_onu_power_hourly` | hourly min/max/avg/count/bad_count | 12 months |
| `olt_onu_power_daily` | daily min/max/avg/count/bad_count/min_time/max_time | 2 years |

Summary should include:

- `stat_time` or `stat_date`
- `olt_device_id`
- `mac_address`
- `if_index`
- `port_if_index`
- `region`
- `sample_count`
- `rx_min`, `rx_max`, `rx_avg`
- `tx_min`, `tx_max`, `tx_avg`
- `bad_count`
- `missing_count`
- `rx_min_time`, `rx_max_time`

### 6.2 CMTS CM Metrics

| Table | Role | Retention |
| --- | --- | ---: |
| `cmts_cm_last` | latest valid CM state | permanent |
| `cmts_cm_his` | valid raw samples | 7 days |
| `cmts_cm_metric_hourly` | hourly SNR/level min/max/avg/count | 12 months |
| `cmts_cm_metric_daily` | daily SNR/level min/max/avg/count/bad_count | 2 years |

### 6.3 OLT Performance

| Table | Role | Retention |
| --- | --- | ---: |
| `olt_perf_device_metric_last` | latest device CPU/memory | permanent |
| `olt_perf_board_metric_last` | latest board CPU/memory | permanent |
| `olt_perf_device_metric_his` | 5 min raw metric points | 30 days |
| `olt_perf_board_metric_his` | 5 min raw metric points | 30 days |
| `olt_perf_device_metric_hourly/daily` | trend summaries | 12 months / 2 years |
| `olt_perf_board_metric_hourly/daily` | trend summaries | 12 months / 2 years |

Deprecated tables:

- `olt_performance_his`
- `olt_performance_last`
- `olt_perf_if_metric_his`
- `olt_perf_if_metric_last`

The interface performance tables must be confirmed unused, then cleaned.

### 6.4 OLT Traffic

The current `olt_octets_his` stores raw counters and is too large for long-term
retention. The useful product data is rate and aggregation.

| Table | Role | Retention |
| --- | --- | ---: |
| `olt_octets_last` | latest raw counters per interface | permanent |
| `olt_if_rate_his` | computed bps samples | uplink/PON 14-30 days, ONU 7 days |
| `olt_if_rate_hourly` | avg/max/min/p95/total_bytes | 12 months |
| `olt_if_rate_daily` | avg/max/p95/total_bytes/peak_time | 2 years |
| `olt_port_profile` | interface type and display metadata | permanent |

Port profile categories:

- `uplink`
- `pon`
- `onu`
- `mgmt`
- `internal`
- `unknown`

Only `uplink` and `pon` should be first-class long-term traffic charts. ONU
traffic can be last-only or short raw history unless a specific use case exists.

Traffic collection should become its own task line instead of staying hidden
inside `onu_local`.

| Task | Scope | Interval | Write path |
| --- | --- | ---: | --- |
| `olt_traffic_core` | uplink and PON ports | 5 min | `olt_octets_last`, `olt_if_rate_*` |
| `olt_traffic_onu` | ONU-facing ports | 15-60 min or disabled | `olt_octets_last`, short `olt_if_rate_his` only |
| `olt_port_profile` | ifName/ifAlias/ifDescr/ifHighSpeed/ifOperStatus | 1 day plus manual refresh | `olt_port_profile` |

Rate computation rules:

- calculate bps from current counter and previous `olt_octets_last`
- reject negative deltas
- reject zero or very small time deltas
- mark large sample gaps
- mark counter reset or device reboot suspicion
- validate utilization against `ifHighSpeed` when available
- store invalid-rate reason instead of forcing a misleading zero

Required rate fields:

- `in_bps`, `out_bps`
- `interval_sec`
- `in_delta_bytes`, `out_delta_bytes`
- `if_speed_bps`
- `util_in_pct`, `util_out_pct`
- `quality_code`
- `sample_gap`
- `counter_reset`

Traffic acceptance must be based on useful ports, not all IF-MIB rows:

- uplink/PON ports have 5 minute samples
- unknown/internal/mgmt ports do not enter long raw history
- chart queries read `olt_if_rate_his/hourly/daily`
- `olt_octets_his` is stopped or reduced after rate tables are stable

## 7. Future Data We Can Collect

| Data | OID/source | Value | Priority |
| --- | --- | --- | --- |
| ARP table | `1.3.6.1.2.1.4.22.1.2` | IP-MAC mapping for terminals/STB | high |
| IP-MIB neighbor table | `1.3.6.1.2.1.4.35.1.4` | newer IP-MAC mapping | medium |
| Bridge FDB | `1.3.6.1.2.1.17.4.3.1.1/2` | L2 MAC learning and port mapping | medium |
| ifName/ifAlias/ifDescr | IF-MIB | port profile and display names | high |
| ifHighSpeed | IF-MIB | utilization percentage | high |
| ifOperStatus/AdminStatus | IF-MIB | port up/down | high |
| LLDP neighbor | LLDP-MIB | topology | medium |
| Board temperature/fan/power | ENTITY/vendor MIB | hardware health | medium |
| ONU offline reason/time | vendor MIB | fault diagnosis | high if OID is reliable |
| ONU distance/temp/voltage/bias | vendor MIB | optical module quality | medium |

Add these as separate task lines only after the current storage model is fixed.

## 7.1 Tooling Decision

Do not introduce a new data platform before the write model is fixed.

| Tool | Decision | Reason |
| --- | --- | --- |
| MySQL | keep as primary operational store | current scale is manageable if raw retention is short and summaries exist |
| ELK | keep for logs, RADIUS/packet analysis, event search | already used by AIOps and better suited for text/event search |
| Kafka/Redpanda | defer for SNMP; consider for RADIUS/packet/event pipeline | SNMP collection is scheduled polling, not a streaming problem yet |
| ClickHouse | defer; prepare schema boundary | useful only if long raw time-series retention is required |
| Prometheus/VictoriaMetrics | not first step | strong for numeric time-series, but frontend and inventory still need relational joins |
| Telegraf/snmpexporter | not first step for OLT/ONU vendor data | generic SNMP tools struggle with current vendor-specific ONU mapping logic |

Recommended near-term platform:

- Go collector remains the SNMP/business parser.
- MySQL stores inventory, latest state, task state, short raw history, summaries.
- ELK stores logs and future RADIUS/packet-derived events.
- Kafka/Redpanda is introduced only when there are multiple event producers or
  when RADIUS/packet analysis needs buffering and replay.
- ClickHouse is introduced only if product requirements demand months of raw
  high-cardinality SNMP history.

Architecture trigger points:

| Trigger | Add |
| --- | --- |
| MySQL remains slow after 7-30 day raw retention and summaries | ClickHouse for raw time-series |
| RADIUS/packet events arrive continuously from multiple servers | Redpanda/Kafka |
| frontend needs second-level numeric metric exploration across months | ClickHouse or VictoriaMetrics |
| collector task coordination becomes multi-node | lightweight task coordinator/lease table before Kafka |

## 8. Implementation Phases

### Phase 1: Stop Bad Writes

Scope:

- normalize and validate MAC in all ONU/CMTS write paths
- skip invalid MAC rows for `his` and `last`
- add raw/invalid/valid counters to task detail where feasible
- change `olt_performance.interval_sec` from 3600 to 300

Acceptance:

- invalid MAC rows no longer appear in `olt_onu_last` or `cmts_cm_last`
- `collector_task_detail` shows valid/invalid row counts or equivalent detail
- `olt_performance` completes within 90 seconds at 5 minute frequency
- `go test ./...` passes

### Phase 2: Add Summary Tables and Jobs

Scope:

- create ONU hourly/daily summary tables
- create CMTS hourly/daily summary tables
- create OLT performance hourly/daily summary tables
- create traffic rate and summary tables
- add idempotent summary jobs

Acceptance:

- yesterday's summary can be regenerated without duplicates
- summary sample count matches source raw rows after filtering
- frontend/API can query trends without reading raw history

### Phase 3: Traffic Refactor

Scope:

- compute rate from `olt_octets_last` and the new sample
- classify interfaces using port profile rules
- store rate samples only for useful interface categories
- keep raw octets history only during migration

Acceptance:

- uplink/PON rate charts match MRTG-style expectations
- computed bps rejects counter reset, negative delta, extreme utilization
- `olt_octets_his` write volume is reduced or stopped
- `olt_if_rate_*` tables become the frontend source

### Phase 4: Cleanup

Scope:

- backfill summaries for retained historical months
- drop old raw partitions
- clean deprecated performance tables
- set recurring maintenance schedule

Acceptance:

- old raw partitions are removed without long blocking writes
- disk usage reduction is visible from partition/table size
- no frontend/API query depends on dropped raw data
- collector writes continue during cleanup

### Phase 5: New Capability Tasks

Scope:

- ARP/FDB/ifAlias/ifHighSpeed collection
- LLDP/topology if needed
- hardware environment metrics if reliable OIDs are confirmed
- RADIUS/packet analysis pipeline on ELK/event storage

Acceptance:

- each new task has task state counters
- each task has a clear retention rule before production enablement
- no new high-volume table is added without summary and cleanup policy

## 9. Data Acceptance Matrix

| Data | Acceptance metric |
| --- | --- |
| ONU latest | `last` rows contain no empty/all-zero MAC; row count matches valid ONU source count |
| ONU power trend | daily summary has min/max/avg and bad_count for every valid ONU with samples |
| External ONU | each source reports fetched, valid, invalid, written; degraded source isolated |
| CMTS latest | `last` rows contain no invalid MAC; external rows remain dominant source |
| CMTS trend | daily summary sample count matches raw valid rows |
| OLT performance | 5 minute task success rate and cost visible; current metrics update every cycle |
| Board performance | board count stable by model; missing board metrics visible |
| OLT traffic | uplink/PON bps calculated from counter delta and validated against capacity |
| Collector health | every task has target, completed, success, fail, row count, cost, lag |
| Cleanup | partition drop or chunk cleanup does not block collector writes beyond agreed window |

## 10. Operational Guardrails

- Avoid DataGrip/full-table `COUNT(*)` on large history tables.
- Use `information_schema.partitions` for size and partition checks.
- Use `DROP PARTITION` for whole-month or whole-day cleanup.
- Use small chunk delete only for partial current-period cleanup.
- Run cleanup outside peak collection windows.
- Before dropping a table/partition, verify the frontend/API no longer queries it.
- Keep a written changelog of production config changes.

## 11. Recommended Immediate Order

1. Implement invalid MAC filtering for ONU and CMTS.
2. Increase OLT performance frequency to 5 minutes.
3. Add summary table DDL for ONU, CMTS, and OLT performance.
4. Backfill and verify summaries for recent data.
5. Implement traffic rate tables and port profile.
6. Switch frontend/API to `last` plus summaries.
7. Clean deprecated performance tables and old raw partitions.
8. Add ARP/FDB/port metadata tasks after the storage model is stable.
