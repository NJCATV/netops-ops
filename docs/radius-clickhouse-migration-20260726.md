# Radius 管理迁移与运维说明（2026-07-26）

## 结论

Radius 采集继续使用 Python，不切换 Go/Erlang。采集数据已从 213 本机
MySQL 单次切换到 212 ClickHouse，233 网管提供统一登录、菜单权限、查询、
CSV 导出和操作审计。ELK 未引入，GOTESSUDP 未作为生产数据源。

生产链路：

```text
213 镜像口 eno1
  -> tcpdump（UDP 1812/1813，8 MiB 内核缓冲）
  -> Python RADIUS 解析/请求响应配对/Accounting 降采样
  -> SQLite WAL spool（断链重放、会话计数状态、镜像重复包去重）
  -> 212 radius_monitor_ch
  -> 233 Radius BFF（JWT + netops.radius）
  -> 网管前端 #/radius
```

## 已吸收的 GOTESSUDP 优点

- Accounting Start、Stop、Interim-Update 分型；
- 以 NAS + Session ID 保存累计计数器状态；
- 使用相邻计数器差值计算流量，计数器回绕/重置时从新值重新起算；
- 账号多 MAC、持续拒绝、NAS 分布、会话和流量排行；
- 采集层与分析查询层解耦。

没有复用 GOTESSUDP 的抓包进程或数据库，避免两个部门的发布、字段定义和
可用性互相绑定。Erlang/Go 并不是当前瓶颈；现场瓶颈是 MySQL 大表、分区维护
和磁盘 I/O。

## 采集可靠性

- `STORAGE_BACKEND` 只能取 `mysql` 或 `clickhouse`，不存在双写分支；
- 生产设置为 `clickhouse`；
- 入库前先写 `/var/lib/radius-monitor/spool.sqlite3`；
- ClickHouse 返回成功后才删除 spool 记录；
- ClickHouse 不可用时指数退避，数据留在本机自动重放；
- `seen_events` 保存 6 小时事件指纹，过滤镜像重复 Accounting 包；
- `session_state` 保存跨重启会话计数器；
- Interim-Update 当前每 300 秒保留一次，Start/Stop 始终保留；
- tcpdump 每 60 秒输出 captured / received / kernel dropped 指标；
- 支持 802.1Q、QinQ、Linux cooked/raw IPv4，跳过非首片 IPv4 分片。

关键告警建议：

| 指标 | 告警条件 |
| --- | --- |
| `lag_seconds` | 连续 3 分钟大于 180 |
| `spool_pending` | 连续增长 5 分钟，或超过 10,000 |
| `sink_retries` | 相邻两个采样周期持续增加 |
| `tcpdump_kernel_dropped` | 相邻采样周期增加 |
| 213 spool 文件 | 超过 15 GiB 预警，20 GiB 严重 |

## ClickHouse 模型

数据库：`radius_monitor_ch`

- `radius_events`：认证与 Accounting 统一事实表；
- `radius_collector_metrics`：抓包、解析、spool、重试、延迟指标；
- `radius_auth_recent` / `radius_accounting_recent`：查询视图。

`radius_events` 使用月分区、`ReplacingMergeTree`、180 天 TTL，并对 NAS、
MAC 和 Session ID 建 Bloom Filter 索引。没有引入物化汇总表，避免写入重试
时聚合重复；当前数据规模下直接按时间窗查询足够快。

ClickHouse 使用两个独立最小权限账号：

- 213 `radius_writer`：仅允许从 213 连接，仅有两张表的 INSERT；
- 233 `radius_reader`：仅允许从 233 连接，仅有 Radius 库 SELECT。

密码只保存在 213 `/opt/radius_monitor/.env` 和 233
`/home/yvesyuan/.netops2026.json`，均为 0600，未写入仓库。

## 网管页面和权限

菜单键：`netops.radius`，仅内部用户可见，最低角色为普通用户。所有接口均使用
网管 `login_required`，并再次校验菜单的 enabled、用户类型和最低角色。

页面：

- `#/radius`：运行总览、认证趋势、数据延迟、spool、重试和内核丢包；
- `#/radius/records`：认证明细、过滤、分页和 CSV；
- `#/radius/reject`：高频认证拒绝；
- `#/radius/multi-mac`：多终端账号；
- `#/radius/analytics`：拒绝原因和 NAS 分布；
- `#/radius/accounting`：上下行增量、趋势和账号排行。

## 生产切换记录

- 11:39:15：旧 MySQL Writer 正常停止；
- 11:39:16：ClickHouse sink 和 tcpdump 启动；
- MySQL 两次间隔检查保持：
  - `auth_recent_log` 最大时间 `2026-07-26 11:39:14.388`；
  - `acct_log` 最大时间 `2026-07-26 11:39:14.410`；
- 实时采集 30,000 条时：重试 0，spool 清空，tcpdump 内核丢包 0；
- API 验收：7 个 Radius JSON 接口、CSV 均为 200；
- 未登录请求为 401，内部普通用户为 200；
- 浏览器验收：菜单、KPI、趋势图和采集链路均正常渲染；
- 213 `nginx`、`radius-web.service`、`radius-cleanup.timer` 已禁用；
- 213 的 80 和 5000 均无监听；防火墙未修改。

没有批量搬迁 MySQL 历史明细。原因是旧库已有约 2.58 亿条活跃明细，且磁盘
曾接近满 I/O；一次性读取会重新制造生产压力。旧 MySQL 当前作为只读归档保留，
新报表从切换时间起在 ClickHouse 连续积累。

## 备份与回滚

213：

- 采集最终备份：
  `/opt/radius_monitor/deploy_backup/20260726-113915-final-cutover`
- Nginx 配置备份：
  `/etc/nginx/conf.d/radius-monitor.conf.pre-migration-20260726-114820`
- `.env` 另有 `pre-clickhouse-*` 和 `pre-credential-reset-*` 备份。

233：

- `/home/yvesyuan/deploy-backups/20260726-113953-radius`
- `.netops2026.json.pre-radius-*`

需要回退采集时：

1. 停止 `radius-sniffer.service`；
2. 将 213 最终备份目录中的 Python 文件和 `.env` 恢复到
   `/opt/radius_monitor`；
3. 确认 `STORAGE_BACKEND=mysql`；
4. 启动 `radius-sniffer.service` 并检查 MySQL 最大时间继续变化。

回退动作会从 ClickHouse 单写切回 MySQL 单写，不应同时启动两个 writer。
是否重新开放旧 Web/80 端口是独立决定，默认不开放。

## 常用检查

```bash
# 213
systemctl status radius-sniffer.service
journalctl -u radius-sniffer.service --since '-10 minutes'
ss -ltnp | grep -E ':(80|5000) '   # 应无输出

# 212
clickhouse-client --query "
SELECT event_type,count(),max(event_time)
FROM radius_monitor_ch.radius_events
GROUP BY event_type"

clickhouse-client --query "
SELECT metric_time,spool_pending,sink_retries,tcpdump_kernel_dropped,last_error
FROM radius_monitor_ch.radius_collector_metrics
ORDER BY metric_time DESC LIMIT 5"

# 233
cd /home/yvesyuan/PycharmProjects/anbo_wx/backend
.venv/bin/python verify_radius_integration.py
```
