# ClickHouse 212 试运行节点

更新日期：`2026-06-29`

## 1. 结论

`172.25.194.212` 已作为 `go-collector` 第一台 ClickHouse 试运行节点启用。

当前定位：

- 承接 SNMP 历史趋势、日报结果、统计结果和后续 AIOps 分析数据。
- 不迁移 `JSCN-236` 上的 MySQL。
- 不影响 236 上当前 collector 运行进程。

## 2. 节点信息

| 项目 | 值 |
| --- | --- |
| Host | `172.25.194.212` |
| SSH | `172.25.194.212:5334` |
| OS | Ubuntu `26.04 LTS` |
| CPU | 8 cores, Intel Xeon E5-2609 v2 |
| Memory | 30 GiB |
| Disk | 7.3 TiB root filesystem |
| ClickHouse | `25.3.14.14` |
| Native port | `9000` |
| HTTP port | `8123` |
| Database | `go_collector_ch` |

## 3. 安装方式

由于 212 当前不能解析外网域名，安装没有依赖 212 直接访问 apt 源。

实际流程：

1. 在本机下载 ClickHouse 官方 deb 包。
2. 通过 SSH/SFTP 上传到 212。
3. 在 212 使用 `dpkg -i` 安装：
   - `clickhouse-common-static_25.3.14.14_amd64.deb`
   - `clickhouse-server_25.3.14.14_amd64.deb`
   - `clickhouse-client_25.3.14.14_amd64.deb`

服务状态：

```bash
systemctl is-active clickhouse-server
```

结果：`active`

## 4. 安全配置

已做的限制：

- `default` 用户限制为本机访问。
- 新增 `go_collector` 用户。
- `go_collector` 用户允许来源：
  - `127.0.0.1`
  - `::1`
  - `172.31.1.236`
- 212 上防火墙当前为 inactive。

配置文件：

- `/etc/clickhouse-server/config.d/go-collector-listen.xml`
- `/etc/clickhouse-server/users.d/go-collector-users.xml`

项目连接凭据保存在 212：

- `/home/njcatv/clickhouse-go-collector.env`

该文件权限为 `0600`，不写入 Git。

## 5. 已创建表

建表脚本：

- `sql/clickhouse_phase1_schema.sql`

当前表：

- `go_collector_ch.onu_optical_sample`
- `go_collector_ch.onu_quality_daily_detail`
- `go_collector_ch.onu_traffic_daily`
- `go_collector_ch.olt_perf_sample`

## 6. 连通性验证

从 `JSCN-236` 到 212：

- TCP `9000`：通过
- TCP `8123`：通过
- HTTP 查询：通过

验证查询：

```sql
SELECT 1
```

结果：`1`

## 7. 后续接入顺序

建议顺序：

1. collector 增加 ClickHouse 配置结构，但默认关闭。
2. 新增 ClickHouse sink，先只写 `onu_optical_sample`。
3. 写失败时落本地 JSONL，避免影响 MySQL 主链路。
4. 跑 24-72 小时后，对比 MySQL 与 ClickHouse 的 15 天趋势查询性能。
5. 再接入每日质差、每日流量和 OLT 性能表。

## 8. 2026-06-30 接入状态

已完成第一条采集链路接入：

- collector 新增 `clickhouse` 配置段。
- 本地 ONU 光功率结果写入 `go_collector_ch.onu_optical_sample`。
- 外部 ONU 同步结果也通过同一 ClickHouse sink 入队写入。
- ClickHouse 写入采用 best-effort 模式：
  - MySQL 主链路仍是主写入路径。
  - ClickHouse 队列满时丢弃待写入样本并记录日志。
  - ClickHouse 写入失败不会阻断 MySQL 写入。

236 已部署新二进制：

- 备份二进制：`bin/collector.bak-20260630-095041`
- 备份配置：`configs/runtime.official.json.bak-20260630-095041`
- 当前配置：`configs/runtime.official.json`
- 当前 ClickHouse 写入：已启用

验证结果：

- collector 已重启，PID `3990410`。
- `sink-clickhouse` 日志连续出现 `clickhouse onu_optical_sample inserted rows=...`。
- 从 236 查询 212 ClickHouse：

```sql
SELECT count(), min(sample_time), max(sample_time)
FROM go_collector_ch.onu_optical_sample;
```

已返回非零行数。
