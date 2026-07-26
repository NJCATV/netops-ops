# Radius 终端链路与六轮审阅记录（2026-07-26）

## 结论

本轮所说的“Redis”全部按用户澄清修正为 **Radius**。系统不再尝试使用 ONU MAC
查询 Radius。两类 MAC 的业务含义和入口已经彻底分开：

- ONU MAC：光接入设备标识，只用于查询 ONU、OLT、PON、光功率、告警和 BOSS 登记；
- 拨号终端 MAC：Radius `Calling-Station-ID`，用于查询认证、Accounting、会话、流量和 GDF；
- 正确联查链路：`拨号终端 MAC -> Radius 成功证据 -> GDF -> BOSS 登记 ONU`；
- 完整一致性链路：在上述链路后增加
  `OLT MAC 地址表 -> 实际 ONU`，再比较 BOSS 登记 ONU 与实际 ONU。

拒绝报文只作为失败证据展示，不能建立“终端 MAC 属于该 GDF”的可信关系。只有
Access-Accept 或 Accounting 记录可以建立终端与账号关联，避免密码试错、攻击或输错账号
污染身份图谱。

## 六轮审阅

### 第一轮：身份语义

- 删除 ONU MAC 到 Radius 的回退查询；
- ONU 页面只在已有 GDF 时加载 Radius 摘要；
- 新增独立的“按拨号终端 MAC”入口；
- GDF/GDC 前缀与 BOSS 数字账号统一归一化；
- 拒绝记录不再扩展 MAC、账号和 ONU 的关联关系。

### 第二轮：抓包协议与解析

- 保留 UDP 1812 认证和 UDP 1813 Accounting；
- 新增 UDP 3799 的 CoA/Disconnect 被动采集；
- 支持 Access-Challenge；
- 补齐 Service-Type、Framed-Protocol、Framed-IP-Netmask、Class、
  Acct-Authentic、Acct-Multi-Session-Id、Connect-Info 和 Error-Cause；
- MAC 统一兼容冒号、短横线、点分和连续 12 位格式；
- 响应报文属性覆盖请求缓存中的旧值；
- 增加 malformed、unknown code、pending、unmatched、expired、eviction 等解析质量指标。

### 第三轮：ClickHouse 与 MySQL 减压

- Radius 新数据继续只写 ClickHouse，不双写 MySQL；
- 213 使用 SQLite WAL spool，在 ClickHouse 暂时不可用时保留并自动重放；
- 原始事实表按月分区、TTL 管理，并增加 NAS、MAC、Session 查询索引；
- 新增控制报文和协议质量字段；
- 建立长期聚合表结构，但不让仅有 INSERT 权限的采集账号触发物化视图查询；
- ELK 暂不引入，避免增加没有明确收益的组件。

上线时曾短暂创建两个物化视图，ClickHouse 以写入者身份执行源表 SELECT，因最小权限策略
拒绝写入。采集数据当时全部留在 spool，没有丢失。物化视图随即移除，spool 自动回放归零，
采集账号仍维持仅 INSERT 权限。后续若启用长期汇总，应使用独立的定时聚合账号。

### 第四轮：一键用户画像

- 支持输入 GDF/GDC 或拨号终端 MAC；
- 展示成功/拒绝/Accounting、活跃会话、NAS、Framed-IP、24 小时/7 天/30 天流量；
- 增加账号多终端、终端多账号、高频拒绝、频繁重连、计数器回退、无 Accounting、
  高上行观察等诊断；
- 多终端和终端共享风险只使用成功认证或 Accounting 证据；
- 增加最近 15 分钟 Framed-IP 冲突分析；
- 增加 NAS Accounting-On/Off 重启事件、CoA/Disconnect 和 Error-Cause 分析；
- 认证、Accounting、控制报文均支持明细筛选，认证明细支持 CSV 导出。

### 第五轮：ONU 与 OLT 一致性

- 终端 MAC 查询会先返回 Radius 证据，再返回 GDF 和 BOSS 预期 ONU；
- 新建 `olt_terminal_mac_snapshot_batch` 和 `olt_onu_terminal_mac_snapshot`，
  为后续 OLT 地址表采集保留标准化快照接口；
- 当前生产环境没有可用的 OLT 终端 MAC 快照，已有 collector-agent 也没有覆盖各厂商
  “终端 MAC -> ONU”的安全查询能力，因此页面明确显示“OLT 映射不可用”，不会把
  BOSS ONU 冒充为实际 ONU；
- 快照到位后，接口已经可以直接给出 `correct_onu`、`wrong_onu`、
  `terminal_not_mapped`、`multi_actual_onu` 等状态。

下一步如要完成实际一致性闭环，应在 OLT 采集器增加厂商适配：按 PON/ONU 获取桥接或
FDB MAC 表，形成带批次、设备、端口、ONU、终端 MAC、采集时间的快照。该操作涉及设备登录
和命令差异，不能用当前光功率采集结果替代。

### 第六轮：页面、权限与生产验收

- Radius 统一纳入网管 JWT、内部用户、菜单和操作审计；
- ONU 页面明确提示两类 MAC 不可混用；
- 终端链路以路径卡片展示“终端 -> Radius GDF -> BOSS ONU -> OLT 实际 ONU”；
- Radius 页面增加运行总览、一键查询、认证/Accounting/控制明细、拒绝风险、多终端和分析；
- 修复“没有认证记录却显示 1970-01-01”的空时间展示；
- 浏览器实际检查了统一菜单、ONU 查询语义、Radius 联动卡片和响应式布局；
- 未登录接口返回 401，普通内部用户和管理员按现有授权均可访问，10 个核心接口、CSV
  和终端联查均返回 200。

## 生产验收数据

2026-07-26 13:38 的连续三个采样周期：

| 指标 | 结果 |
| --- | ---: |
| 认证记录 | 49,458 |
| Accounting 记录 | 14,877 |
| CoA/Disconnect 控制记录 | 252 |
| ClickHouse 重试 | 0 |
| spool 待发送 | 0 |
| tcpdump 内核丢包 | 0 |
| malformed / unknown code | 0 / 0 |
| last_error | 空 |

示例终端 `68:dd:b7:c7:51:11` 已通过成功 Radius 证据解析为 `GDF2795313`，并找到
BOSS 预期 ONU。由于 OLT 快照尚为空，最终状态按事实返回 `olt_mapping_unavailable`。

## 生产备份

- 213：`/opt/radius_monitor/deploy_backup/20260726-132341-terminal-path`
- 233：`/home/yvesyuan/deploy-backups/20260726-132300-radius-terminal-path`
- 233 空时间修复：`/home/yvesyuan/deploy-backups/20260726-133510-radius-epoch-fix`

213 的 80/5000 端口仍无监听，防火墙未修改。

## 协议依据

- RFC 2866：Accounting Start/Stop、Accounting-On/Off、Acct-Delay-Time；
- RFC 5176：Disconnect/CoA 报文代码 40–45 和 Error-Cause；
- FreeRADIUS 官方 SQL accounting queries：Start、Interim、Stop 的会话与计数器处理；
- FreeRADIUS linelog/detail 文档：结构化记录和故障留痕思路。
