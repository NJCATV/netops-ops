# ONU 终端 MAC 与 GDF 拨号一致性审计

记录时间：2026-06-17

## 1. 背景目标

本次工作的最终目标不是单纯采集 OLT 下挂终端 MAC，而是判断：

- `boss_user_info` 中记录的 `GDF账号 -> ONU MAC` 是公司业务开通规范关系。
- Radius 抓包表中记录的 `GDF账号 -> 终端MAC` 是用户实际拨号行为。
- OLT MAC 表采集出的 `终端MAC -> ONU MAC` 可以把 Radius 实际拨号终端落到具体 ONU。

因此可以形成闭环：

```text
BOSS 规范关系:
GDF账号 -> 应开ONU

Radius 实际拨号:
GDF账号 -> 实际终端MAC

OLT MAC 表:
实际终端MAC -> 实际ONU

最终判断:
应开ONU 是否等于 实际ONU
```

只对可观测范围做判断：目前只覆盖已经验证“宽带 VLAN 的 MAC 表能显示到 Onu 详细口子”的 H3C7510 OLT。

## 2. 已落地的数据表

### 2.1 boss_user_info

来源文件：

```text
南京地区截止4.30 ONU.xlsx
```

导入目标表：

```text
go_collector.boss_user_info
```

字段映射：

```text
公司         -> company
证号         -> id_number
区域         -> region
网格         -> grid
入户时间日期 -> visit_datetime
ONU序列号    -> onu_serial_number
```

Excel 中没有姓名、地址、电话，导入时：

```text
name = ''
address = NULL
phone1 = NULL
phone2 = NULL
```

导入统计：

```text
总行数: 346195
证号/GDF ID 去重数: 346195
ONU 序列号去重数: 344646
12 位 ONU 序列号: 340795
非 12 位 ONU 序列号: 5400
重复 ONU 序列号组: 308
```

说明：

- `id_number` 作为 BOSS 侧 GDF ID。
- `onu_serial_number` 已清洗为小写、去掉非十六进制字符的字符串，用于和 `onu_mac` 匹配。
- Radius 表中的账号形态是 `GDF2720009` 这类格式，后续比较时应同时保留原始账号和去掉 `GDF` 前缀后的规范化账号。

### 2.2 olt_onu_terminal_mac_once

最终精简映射表：

```text
go_collector.olt_onu_terminal_mac_once
```

字段：

```text
olt_device_id
olt_name
vlan_id
if_index
port_name
onu_mac
terminal_mac
gdf_id
```

含义：

- 一行表示一个 `ONU + 终端MAC` 映射。
- 少数 ONU 会对应多个终端 MAC，因此行数可能大于 ONU 台数。
- `gdf_id` 当前来自 BOSS 表，表示该 ONU 在 BOSS 侧对应的 GDF ID；这不是 Radius 实际拨号账号。

生成规则：

1. 通过堡垒机登录可查 H3C7510 OLT。
2. 对每台 OLT 的宽带 VLAN 执行只读命令：

```text
display mac-address vlan <vlan_id>
```

3. 只保留 `Port/Nickname` 为 `Onu...` 的终端 MAC。
4. 与 `olt_onu_last` 通过 `uplink_port = Onu口名` 匹配。
5. ONU 必须满足：

```sql
mac_address IS NOT NULL
AND uplink_port REGEXP '^Onu[0-9]+/[0-9]+/[0-9]+:[0-9]+'
AND (rx_power IS NOT NULL OR tx_power IS NOT NULL)
```

6. 同一个 `Onu口` 在 `olt_onu_last` 里可能有重复/历史记录，取一条：

```text
优先 status = 1
再按 query_time 最新
再按 id 最大
```

7. 用 `boss_user_info.onu_serial_number = olt_onu_terminal_mac_once.onu_mac` 回填 BOSS 侧 `gdf_id`。

### 2.3 olt_router_mac_raw_once

原始命令采集表：

```text
go_collector.olt_router_mac_raw_once
```

用途：

- 保存 OLT `display mac-address vlan <vlan_id>` 原始结果。
- 用于排查某台 OLT 为什么 raw 有数据但最终表没有数据。
- 最终业务判断以 `olt_onu_terminal_mac_once` 为主。

## 3. 本轮 OLT 采集统计

本轮批次号：

```text
routermac_all_20260617104415
```

本地汇总文件：

```text
outputs/routermac_all_20260617104415_summary.tsv
```

采集范围：

```text
34 个 OLT/VLAN 采集任务
33 台 H3C7510 设备
所有任务 status = ok
命令截断数 = 0
```

注意：`337 城北OLT-H3C7510-1` 采了两个 VLAN，因此任务数比设备数多 1。

原始与最终结果：

```text
OLT MAC raw 行: 18919
其中 Onu 口 raw 行: 18851

最终 terminal 映射行数: 14174
最终涉及 ONU 台数: 13176
最终涉及终端 MAC 数: 14173

有 terminal 映射且匹配到 BOSS gdf_id 的 ONU 台数: 11303
有 terminal 映射但未匹配到 BOSS gdf_id 的 ONU 台数: 1873
```

本轮处理 OLT 中，`olt_onu_last` 里符合“真实 ONU”条件的 ONU 总数：

```text
有 ONU MAC
有光功率
有标准 Onu 口名

共 25227 台
```

因此：

```text
真实 ONU 中，本次观察到终端 MAC 的比例: 13176 / 25227 = 52.2%
有终端 MAC 的 ONU 中，匹配到 BOSS GDF 的比例: 11303 / 13176 = 85.8%
```

两个特殊任务：

```text
337 / VLAN 2300: raw_onu 133，最终 0
380 / VLAN 2287: raw_onu 930，最终 0
```

原因：raw 能看到 `Onu...` 口，但按“`olt_onu_last` 可匹配 + 光功率有值”的规则没有形成最终记录。

## 4. Radius 实际拨号数据

Radius 数据源：

```text
host: 172.25.194.213
port: 3306
user: radius
password: 已按运维提供口径使用，文档不保存明文
database: radius_monitor
table: auth_user_mac_10m
```

表结构已只读确认：

```text
bucket_start   datetime(3)  -- 10分钟桶起始时间
username       varchar(128) -- GDF账号，例如 GDF2720009
mac_addr       varchar(20)  -- 实际拨号终端MAC，例如 78:44:fd:ce:e9:b3
request_count  bigint
accept_count   bigint      -- 成功认证次数
reject_count   bigint
nas_ip
nas_port
nas_identifier
nas_port_id
main_reason
first_seen
last_seen
updated_at
```

样例：

```text
username      = GDF2720009
mac_addr      = 78:44:fd:ce:e9:b3
accept_count  = 1
nas_port_id   = slot=0;subslot=0;port=16;vlanid=11;vlanid2=2328;
```

后续判断实际拨号关系时，建议优先使用：

```sql
accept_count > 0
```

只拒绝、账号不存在等记录先不要直接当作“实际成功使用”，可单独统计为异常认证尝试。

## 5. 下一步审计逻辑

### 5.1 规范化

GDF 账号规范化：

```text
BOSS:  id_number
Radius: username

radius_gdf_id = 去掉 username 前缀 GDF 后的部分
boss_gdf_id   = id_number 原值
```

注意：

- `id_number` 有前导 0 的情况，不能转整数。
- 比较时应保留字符串。
- 可同时保留 `radius_username` 原值，便于追溯。

MAC 规范化：

```text
78:44:fd:ce:e9:b3 -> 7844fdcee9b3
78-44-FD-CE-E9-B3 -> 7844fdcee9b3
```

### 5.2 BOSS 侧应开关系

从 `boss_user_info` 得到：

```text
boss_gdf_id -> expected_onu_mac
```

SQL 口径：

```sql
SELECT
  id_number AS boss_gdf_id,
  onu_serial_number AS expected_onu_mac,
  company,
  region,
  grid,
  visit_datetime
FROM boss_user_info
WHERE id_number <> ''
  AND onu_serial_number <> '';
```

### 5.3 Radius 侧实际拨号关系

从 `radius_monitor.auth_user_mac_10m` 得到：

```text
actual_gdf_id -> actual_terminal_mac
```

建议先限定时间窗口，例如最近 7 天或最近 24 小时，避免历史迁移行为影响当前判断。

基础口径：

```sql
SELECT
  username,
  mac_addr,
  SUM(request_count) AS request_count,
  SUM(accept_count) AS accept_count,
  SUM(reject_count) AS reject_count,
  MIN(first_seen) AS first_seen,
  MAX(last_seen) AS last_seen
FROM radius_monitor.auth_user_mac_10m
WHERE bucket_start >= ?
  AND accept_count > 0
GROUP BY username, mac_addr;
```

如果同一个 GDF 在窗口内对应多个终端 MAC：

- 保留全部明细用于审计。
- 可选一个主用终端用于主判定：优先 `accept_count` 最大，再按 `last_seen` 最新。

### 5.4 实际终端落到实际 ONU

用 Radius 的 `actual_terminal_mac` 关联：

```text
radius actual_terminal_mac
  -> olt_onu_terminal_mac_once.terminal_mac
  -> actual_onu_mac / actual_olt / actual_port
```

关联条件：

```sql
normalized(radius.mac_addr) = olt_onu_terminal_mac_once.terminal_mac
```

得到：

```text
actual_gdf_id
actual_terminal_mac
actual_onu_mac
actual_olt_device_id
actual_olt_name
actual_vlan_id
actual_if_index
actual_port_name
```

### 5.5 应开 ONU 与实际 ONU 对比

核心判断：

```text
expected_onu_mac == actual_onu_mac
```

分类建议：

```text
correct_onu
  BOSS 应开 ONU 与 Radius 实际终端所在 ONU 一致。

wrong_onu
  Radius 实际终端能定位到 ONU，但 actual_onu_mac != expected_onu_mac。

no_radius_seen
  BOSS 有账号，但指定时间窗口内没有成功 Radius 拨号记录。

radius_terminal_not_mapped
  Radius 有成功拨号终端 MAC，但该 terminal_mac 不在当前 OLT 终端映射表里。
  可能原因：不在本轮可查 H3C7510 范围、非当前在线、其他厂家设备、MAC 表未学到。

expected_onu_out_of_scope
  BOSS 应开 ONU 不属于本轮可观测 OLT 范围。
  不能用当前数据判断“是否拨在正确 ONU”，只能标记为不可判定。

multi_actual_onu
  同一个 GDF 在窗口内实际出现在多个 ONU。
  如果其中包含 expected_onu，可标记为 mixed；否则是高风险异常。

radius_reject_only
  只有 reject，没有 accept，不作为成功实际使用，但可以作为账号异常尝试单独统计。
```

## 6. 推荐落地表

建议新建一次性审计结果表：

```text
gdf_onu_dial_audit_once
```

字段建议：

```text
gdf_id
radius_username
expected_onu_mac
expected_company
expected_region
expected_grid
expected_visit_datetime

actual_terminal_mac
actual_onu_mac
actual_olt_device_id
actual_olt_name
actual_vlan_id
actual_if_index
actual_port_name

radius_request_count
radius_accept_count
radius_reject_count
radius_first_seen
radius_last_seen

audit_status
audit_reason
```

可选补充表：

```text
gdf_onu_dial_audit_detail_once
```

用途：保留一个 GDF 多个终端、多台 ONU 的明细，避免主表只保留主用终端时丢失证据。

## 7. 关键注意事项

1. 分母要分清：
   - `boss_user_info` 全量是 346195 个 GDF。
   - 当前 OLT 终端映射只覆盖一部分 H3C7510。
   - 不能把不可观测范围的 GDF 直接判为正确或错误。

2. 终端 MAC 表是时点数据：
   - OLT MAC 表只反映采集时设备学到的 MAC。
   - Radius 是时间窗口聚合数据。
   - 两者时间窗口不一致时，可能出现 Radius 有终端但 OLT 当前表无终端。

3. 只用成功认证判断实际使用：
   - `accept_count > 0` 作为实际拨号依据。
   - `reject_count > 0` 且 `accept_count = 0` 单独统计，不进入“实际使用 ONU”主判断。

4. GDF 前导 0 不可丢：
   - `boss_user_info.id_number` 必须按字符串处理。
   - Radius `username` 去掉 `GDF` 前缀后也按字符串处理。

5. 当前 `olt_onu_terminal_mac_once.gdf_id` 表示 BOSS 侧 ONU 归属账号，不是 Radius 实际拨号账号。
   - 真正判断时，应以 Radius `username` 作为“实际使用账号”。

## 8. 实操口径补充：Radius 大表与报告分母

### 8.1 不建议直接反复查询 Radius 在线大表

`radius_monitor.auth_user_mac_10m` 是全域 Radius 10 分钟聚合表，并且一直在写入。

直接在这张表上反复做复杂 join 有几个问题：

- 表很大，查询容易慢。
- 表持续写入，同一份报告在不同时间跑可能结果不完全一致。
- 它是全域拨号数据，不只包含本轮 34 台 H3C7510 范围。
- 远程库和本地 `go_collector` 库跨库 join 不方便，也不适合反复压生产库。

因此建议先做一张本地分析快照表，只拉取本次报告需要的时间窗口和字段。

### 8.2 建议的 Radius 清洗快照表

建议在 `go_collector` 库中新建一次性快照表：

```text
radius_auth_user_mac_once
```

推荐字段：

```text
snapshot_id
bucket_start
radius_username      -- 原始 username，例如 GDF2720009
gdf_id               -- 去掉 GDF 前缀后的账号，例如 2720009
terminal_mac         -- 规范化后的终端 MAC，例如 7844fdcee9b3
request_count
accept_count
reject_count
nas_ip
nas_identifier
nas_port_id
main_reason
first_seen
last_seen
updated_at
```

其中：

```text
radius_username = auth_user_mac_10m.username
gdf_id = 去掉 username 前缀 GDF/gdf 后的字符串
terminal_mac = 去掉 mac_addr 中冒号、横线、点号等非十六进制字符后转小写
```

注意：

- Radius 里的账号格式是 `GDF + 账号`，不是纯数字。
- BOSS 里的 `boss_user_info.id_number` 是纯账号字符串，可能有前导 0，不能转整数。
- 所以后续比较必须按字符串：

```text
UPPER(radius.username) 去掉开头 GDF == boss_user_info.id_number
```

### 8.3 快照应按时间窗口固定

报告必须指定时间窗口，例如：

```text
最近 1 天
最近 7 天
指定日期: 2026-06-10 00:00:00 ~ 2026-06-17 00:00:00
```

建议初版报告用最近 7 天成功认证记录：

```sql
accept_count > 0
```

原因：

- 成功认证才代表“实际使用/实际拨号成功”。
- 只 reject 的记录可能是账号输错、历史残留、非法尝试或账号不存在，不应直接判定为实际使用 ONU。

只 reject 的记录可以单独做辅助统计：

```text
reject_only
```

但不进入主审计分母。

### 8.4 全域 Radius 如何缩小到 34 台样例

Radius 表是全域拨号数据，不能直接用 Radius 的总 GDF 数作为本报告分母。

本次报告的样例范围应由 OLT 终端映射表限定：

```text
olt_onu_terminal_mac_once
```

这个表表示：

```text
在这 34 个 OLT/VLAN 任务中，我们实际观察到：
终端MAC -> 实际ONU
```

因此 Radius 进入本报告范围有两种口径。

#### 口径 A：以 OLT 映射表为入口，推荐

先拿本轮可观测终端 MAC 集合：

```sql
SELECT DISTINCT terminal_mac
FROM olt_onu_terminal_mac_once;
```

再从 Radius 快照中匹配：

```text
radius.terminal_mac IN 本轮 OLT 终端 MAC 集合
```

得到的 Radius 记录才属于“这 34 台样例范围内真实拨号到这些 ONU 的账号”。

优点：

- 分母清楚：只讨论本轮能定位到 ONU 的终端。
- 不会把全域 Radius 账号混进来。
- 可以回答“这些 ONU 上实际是谁在拨号”。

#### 口径 B：以 BOSS 应开 ONU 为入口，辅助

先拿 BOSS 中应开到本轮 34 台可观测 ONU 的 GDF：

```text
boss_user_info.onu_serial_number IN 本轮可观测 ONU MAC 集合
```

再看这些 GDF 在 Radius 里有没有成功拨号，以及拨号终端最终落在哪个 ONU。

优点：

- 可以回答“这些开户在本范围 ONU 上的 GDF，是否真的在正确 ONU 上使用”。

缺点：

- 如果该 GDF 实际拨到其他非本轮可观测 OLT，当前 OLT 映射表可能无法定位实际 ONU，只能标记为 `radius_terminal_not_mapped` 或 `out_of_scope`。

最终报告建议同时给两个视角：

```text
视角 1：以实际拨入本范围 ONU 的 Radius 账号为分母
视角 2：以 BOSS 开户在本范围 ONU 的账号为分母
```

### 8.5 核心审计 join

#### BOSS 应开关系

```text
boss_user_info.id_number
  -> boss_user_info.onu_serial_number
```

记为：

```text
boss_gdf_id
expected_onu_mac
```

#### Radius 实际拨号关系

```text
radius_auth_user_mac_once.radius_username
radius_auth_user_mac_once.gdf_id
radius_auth_user_mac_once.terminal_mac
```

记为：

```text
actual_gdf_id
actual_terminal_mac
```

#### OLT 实际终端归属

```text
olt_onu_terminal_mac_once.terminal_mac
  -> olt_onu_terminal_mac_once.onu_mac
```

记为：

```text
actual_terminal_mac
actual_onu_mac
actual_olt_device_id
actual_olt_name
actual_port_name
```

#### 最终判断

```text
boss_gdf_id = actual_gdf_id
expected_onu_mac = actual_onu_mac
```

分类：

```text
correct_onu
  actual_gdf_id 在实际拨号，且 actual_onu_mac = BOSS expected_onu_mac。

wrong_onu
  actual_gdf_id 在实际拨号，actual_terminal_mac 已定位到本轮 OLT ONU，
  但 actual_onu_mac != BOSS expected_onu_mac。

unknown_boss_gdf
  Radius 实际拨号账号不在 boss_user_info 中。

radius_terminal_not_mapped
  Radius 账号存在，终端 MAC 存在，但终端 MAC 不在本轮 OLT 映射表中。

boss_gdf_no_radius_accept
  BOSS 中应开在本范围 ONU 的账号，在时间窗口内没有成功认证记录。

multi_actual_onu
  同一个 GDF 在时间窗口内成功出现在多个实际 ONU。

multi_actual_terminal
  同一个 GDF 在时间窗口内对应多个终端 MAC。
```

### 8.6 报告最终要回答的问题

报告至少要回答两组问题。

#### 问题 1：有多少 GDF 没按开户地址使用 ONU

以 BOSS 开户在本轮可观测 ONU 的 GDF 为分母：

```text
boss_scope_gdf_count
correct_onu_gdf_count
wrong_onu_gdf_count
no_radius_accept_gdf_count
radius_terminal_not_mapped_gdf_count
multi_actual_onu_gdf_count
```

其中真正能下“没按开户地址使用 ONU”结论的是：

```text
wrong_onu
```

`no_radius_accept` 和 `radius_terminal_not_mapped` 只是不可确认或未观察到成功使用，不应和 `wrong_onu` 混在一起。

#### 问题 2：有多少 ONU 被错误 GDF 使用

以本轮 `olt_onu_terminal_mac_once` 中实际有终端 MAC 的 ONU 为分母：

```text
actual_onu_count
actual_onu_with_radius_gdf_count
actual_onu_correct_gdf_count
actual_onu_wrong_gdf_count
actual_onu_unknown_gdf_count
```

判断方式：

```text
实际在该 ONU 上拨号的 GDF
  与
BOSS 中该 ONU 对应的 GDF
```

不一致则为：

```text
actual_onu_wrong_gdf
```

如果一个 ONU 有多个终端 MAC 或多个 Radius GDF，报告中要保留明细作为证据。

### 8.7 推荐输出表

主报告表：

```text
gdf_onu_dial_audit_once
```

一行一个 `GDF + 实际终端MAC + 实际ONU` 证据。

字段：

```text
snapshot_id
boss_gdf_id
radius_username
radius_gdf_id

expected_onu_mac
expected_company
expected_region
expected_grid

actual_terminal_mac
actual_onu_mac
actual_olt_device_id
actual_olt_name
actual_vlan_id
actual_if_index
actual_port_name

radius_request_count
radius_accept_count
radius_reject_count
radius_first_seen
radius_last_seen

audit_status
audit_reason
```

汇总报告表或导出 Excel：

```text
summary_by_status
wrong_gdf_detail
wrong_onu_detail
multi_onu_gdf_detail
unmapped_radius_terminal_detail
```

### 8.8 本报告的正确叙述方式

不要说：

```text
全南京有多少 GDF 错误使用 ONU
```

因为当前 OLT 终端映射只覆盖小范围样例。

应表述为：

```text
在本次 34 个 H3C7510 OLT/VLAN 样例范围内，
基于 OLT MAC 表、BOSS 开户 ONU、Radius 成功认证记录，
发现有多少 GDF 实际拨号 ONU 与 BOSS 开户 ONU 不一致。
```

这才是本轮数据能支撑的结论。
