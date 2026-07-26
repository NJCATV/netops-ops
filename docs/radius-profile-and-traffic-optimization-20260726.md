# Radius 流量、用户画像与 ONU 联动优化（2026-07-26）

## 结果

- 213 继续独立抓取认证与 Accounting，不读取、依赖或双写同事项目。
- 现场华为 RADIUS+ 的 `Acct-Input/Output-Octets` 实际单位为 KiB；采集层统一乘
  `1024` 后以字节写入 ClickHouse。
- 已有 ClickHouse Accounting 数据在停采、spool 为 0 的边界内一次性换算，
  新旧记录口径一致。
- 会话差分键由 `NAS + Session` 修正为
  `GDF + NAS + Session`，避免不同账号复用会话号时互相串流量。
- Interim 采样由 300 秒调整为 60 秒；Start/Stop 始终保留。
- 华为 VSA 已兼容 Subscriber-ID、MAC、上下行平均速率和 Product-ID。当前现场
  报文主要使用标准 User-Name、Calling-Station-ID，VSA 字段为空不影响主流程。
- 233 新增 Radius 一键查询、ONU 自动联查、全局会话/流量分析。

## GOTESSUDP 只读核验

经 236 跳板机读取同事 `mytessgo` 数据库：

- 当天原始表约 165 万条、12.2 万账号、24.4 万会话；
- `gdf_hourly_traffic_20260726` 约 135 万行、11.9 万账号；
- 小时表的列名和注释写作 bytes，但源码累加的是现场原始 KiB；
- 当天异常表约有 8.8 万条 `pcdn_suspect`、4.8 万条
  `frequent_reconnect`、1.1 万条 `multi_mac`。

因此吸收会话差分、小时账号聚合、回退、多 MAC 和重连思路，但不复制其 MySQL
日分表、原始包全量写入和高敏感度异常判定。我们使用 ClickHouse 动态聚合，并将
高上行行为标记为“需要观察”，不直接判定 PCDN。

## 一键查询

入口：`#/radius/search`

支持输入完整 GDF/GDC 或 MAC，返回：

- 账号、Subscriber-ID、MAC 关联；
- 最近认证结果、原因和时间；
- 24 小时、7 天、30 天上下行流量；
- 会话状态、NAS、终端 IP、会话时长和增量；
- 最近认证/计费记录；
- 高频拒绝、多 MAC、频繁重连、计数器回退、无 Accounting、
  疑似高上行结构等问题；
- 健康分和跳转 FTTH ONU 查询。

诊断规则只提供排障线索。高上行观察当前要求近 24 小时上行至少 20 GiB 且
上下载比至少 4，避免复制同事项目的高误报口径。

## ONU 联动

单台 ONU 查询成功后，前端仅在存在 `gdf_account` 时加载 Radius 画像摘要；没有账号时
不会使用 ONU MAC 查询 Radius，因为 ONU MAC 与用户拨号终端 MAC 的业务含义不同：

- 健康分；
- 最近认证；
- 24 小时流量；
- 会话/MAC 数；
- 首要诊断结论；
- 完整 Radius 画像链接。

另设“按拨号终端 MAC”查询：`终端 MAC -> Radius 成功证据 -> GDF -> BOSS ONU`。
拒绝记录只作为失败证据，不能建立终端、账号和 ONU 的可信关联。

常见 1366/1440 笔记本宽度下，ONU 工作台改为上下布局，避免原有横向溢出。

## 全局分析

`#/radius/analytics` 增加：

- 最近 15 分钟活跃会话；
- 窗口内 Accounting Start 至少 3 次的重连账号；
- Accounting Stop 下线原因；
- GDF 上行、下行、总量、比例和会话数；
- 保守的高上行流量结构观察。

`#/radius/accounting` 增加：

- 明确的 KiB 转字节与首次基线说明；
- 有效增量、计数器回退、Start/Stop/Interim 数据质量；
- 可点击进入一键画像的 GDF 排行。

## 生产验收

- 切换前 spool：0；
- 切换后 3 分钟：6,672 条 Accounting、5,904 个 GDF/GDC，
  62 条有效增量、约 40.7 MiB；
- ClickHouse 重试：0；
- tcpdump 内核丢包：0；
- Radius JSON/CSV、普通内部用户权限和一键画像接口全部返回 200；
- 未认证请求返回 401；
- 213 的 80、5000 继续保持无监听；防火墙未修改。

生产备份：

- 213：`/opt/radius_monitor/deploy_backup/20260726-121540-radius-flow-profile`
- 233：`/home/yvesyuan/deploy-backups/20260726-121747-radius-profile`
- 233：`/home/yvesyuan/deploy-backups/20260726-122245-radius-analytics`
- 233：`/home/yvesyuan/deploy-backups/20260726-123219-radius-responsive`
