# Go Collector Data Retention Plan

## Decision

Keep MySQL as the operational database for device inventory, task state, and
latest snapshots. Stop treating MySQL history tables as infinite storage.

Use this split:

- `*_last`: operational latest state, kept permanently.
- `collector_task_*` and `*_collect_round_his`: operational audit, kept in MySQL
  for at least 90 days.
- high-volume raw history (`olt_octets_his`, `olt_onu_his`, `cmts_cm_his`): keep
  raw detail for 7 to 14 days in MySQL.
- daily rollups: keep long-term min/max/avg/count quality and traffic summaries.
- optional cold archive: export deleted raw partitions to object/file storage if
  later forensic replay is needed.

ELK is useful for logs and troubleshooting, but it should not replace the raw
history store for structured time-series data.

## Current Scale

Approximate production table size on 2026-05-27:

| table | rows | size |
| --- | ---: | ---: |
| `olt_octets_his` | 367M | 132 GB |
| `olt_onu_his` | 118M | 43 GB |
| `cmts_cm_his` | 33M | 14 GB |

`olt_octets_his` is the primary pressure point because index size is already much
larger than data size.

## Recommended Retention

| Data | Raw Retention | Rollup Retention | Notes |
| --- | ---: | ---: | --- |
| OLT ONU optical power | 14 days | 2 years | daily min/max/avg/count per device + MAC/if_index |
| OLT octets/speed | 7 days | 2 years | daily max in/out speed and total counter delta per device + MAC/if_index |
| CMTS CM SNR/level | 14 days | 2 years | daily min/max/avg/count per CMTS + MAC |
| collect round status | 90 days | optional monthly summary | needed for failure trend and operations review |
| task state overview/detail | latest/current rows | not applicable | operational state only |

## Schema Direction

Create daily rollup tables before deleting raw history:

```sql
CREATE TABLE IF NOT EXISTS olt_onu_daily_stat (
  stat_date date NOT NULL,
  olt_device_id int NOT NULL,
  region varchar(20) NULL,
  mac_address varchar(20) NOT NULL,
  if_index varchar(20) NULL,
  sample_count int NOT NULL,
  rx_min float NULL,
  rx_max float NULL,
  rx_avg float NULL,
  tx_min float NULL,
  tx_max float NULL,
  tx_avg float NULL,
  first_query_time datetime NULL,
  last_query_time datetime NULL,
  PRIMARY KEY (stat_date, olt_device_id, mac_address),
  KEY idx_onu_daily_device_date (olt_device_id, stat_date)
);

CREATE TABLE IF NOT EXISTS olt_octets_daily_stat (
  stat_date date NOT NULL,
  olt_device_id int NOT NULL,
  region varchar(20) NULL,
  mac_address varchar(20) NOT NULL,
  if_index varchar(20) NULL,
  uplink_port varchar(50) NULL,
  sample_count int NOT NULL,
  in_speed_max float NULL,
  out_speed_max float NULL,
  in_speed_avg float NULL,
  out_speed_avg float NULL,
  first_query_time datetime NULL,
  last_query_time datetime NULL,
  PRIMARY KEY (stat_date, olt_device_id, mac_address),
  KEY idx_octets_daily_device_date (olt_device_id, stat_date)
);

CREATE TABLE IF NOT EXISTS cmts_cm_daily_stat (
  stat_date date NOT NULL,
  cmts_device_id int NOT NULL,
  region varchar(20) NULL,
  mac_address varchar(17) NOT NULL,
  sample_count int NOT NULL,
  snr_min float NULL,
  snr_max float NULL,
  snr_avg float NULL,
  lvl_min float NULL,
  lvl_max float NULL,
  lvl_avg float NULL,
  first_query_time datetime NULL,
  last_query_time datetime NULL,
  PRIMARY KEY (stat_date, cmts_device_id, mac_address),
  KEY idx_cmts_daily_device_date (cmts_device_id, stat_date)
);
```

Partition the three raw history tables by `query_time` after rollups exist. Use
daily partitions for `olt_octets_his`; monthly partitions are acceptable for the
smaller history tables only if deletion latency is acceptable. Dropping old
partitions should replace large `DELETE` jobs.

## Rollout

1. Add rollup tables and a daily rollup job for yesterday's data.
2. Backfill the last 14 days into rollup tables.
3. Convert raw history tables to `query_time` partitions.
4. Keep `olt_octets_his` raw data for 7 days, `olt_onu_his` and `cmts_cm_his`
   raw data for 14 days.
5. Add a daily maintenance job that verifies rollup completion, then drops old
   partitions.
6. Add dashboard checks for ingestion lag, failed device count, and slow-device
   count.

ClickHouse is the best next step if long raw retention is later required. It can
store the high-volume append-only history cheaply while MySQL keeps latest state
and operational metadata.
