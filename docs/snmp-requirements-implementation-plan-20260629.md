# SNMP 采集真实需求实施路径

更新日期：`2026-06-29`

## 1. 总体判断

用户真实需求与当前 `go-collector` 的演进方向一致：系统需要从“能采集并落库”升级为“当前状态、短期趋势、每日结果、长期统计、异常候选”分层清晰的采集与分析底座。

当前项目不应推倒重做，也不应立即把需求文档里的 `onu_current` 等表原样全量替换现有表。线上已经有可运行的采集链路、热表、聚合表和任务状态表，第一阶段应该保留现有写入模型，在它上面补齐查询视图、每日结果表、统计表和事件候选表。

当前核心原则：

- `olt_onu_last` 继续作为 ONU 当前状态主表。
- `olt_onu_his` 继续作为短期历史过渡表，但不作为长期查询主入口。
- `olt_onu_power_hourly` / `olt_onu_power_daily` 作为光功率趋势主查询层。
- MySQL 先承载第一阶段当前查询、日报结果和前端 API。
- ClickHouse 作为第二阶段历史分析库试运行，不抢第一阶段主链路。
- AIOps 只消费基础异常候选和趋势数据，复杂归因不放进 collector。

## 2. 分阶段任务拆解

### Task 0：运行基线与风险边界

目标：后续改造前，明确生产运行状态、慢设备、外部源降级和写库压力。

产出：

- 固化当前运行状态记录。
- 明确当前 PID、版本、配置、数据目录、日志目录。
- 定义生产变更规则：schema 脚本先评审，运行配置和进程变更单独确认。

验收：

- `go test ./...` 通过。
- `collector_task_overview/detail` 能反映当前任务状态。
- 栖霞外部源超时、慢设备拖尾等已知问题不被误判为新故障。

状态：已完成基线检查，当前版本 `c79a4a0`，生产进程正常运行。

### Task 1：当前查询层

目标：先让 ONU MAC 当前查询稳定、字段统一、可给 API/前端使用。

产出：

- `v_onu_current` 查询视图。
- 确认 `olt_onu_last.mac_address` 有单列索引。
- 查询字段包含 OLT、PON/ONU 口、光功率、状态、质差规则、数据来源、数据新鲜度、业务资料。

实现策略：

- 不新增 `onu_current` 实表，避免和 `olt_onu_last` 双写不一致。
- API 入参必须使用 `internal/macutil.Normalize` 同口径标准化。
- 后续如果历史 MAC 格式不统一，再增加 `mac_norm` 字段或生成列。

### Task 2：每日质差清单

目标：支持“按天查询和导出质差 ONU”，而不是临时扫当前表或事件表。

产出：

- `onu_quality_daily_detail`。
- summary 任务新增日报生成步骤。
- 支持按日期、区域、OLT、PON、质差类型筛选。

实现策略：

- 第一版从 `olt_onu_last` 或 `olt_onu_power_daily` 固化每日弱光清单。
- 规则先复用 `quality.EvaluateONU` 的当前阈值版本。
- 每日任务采用按 `stat_date` 删除再写入的可重跑模型。

### Task 3：ONU 每日流量结果

目标：把 IF/octet 原始采集转为可查询的 ONU/端口每日流量结果。

产出：

- `onu_traffic_daily`。
- 自然日口径、counter delta、异常质量码。
- 单 ONU 或端口每日流量查询 API。

实现策略：

- 保留 `olt_octets_last` 和窗口采样作为 delta 输入。
- 不再让前端直接读 `olt_octets_his`。
- counter 回绕、采样间隔异常、设备重启时写 `quality_code`，不强行写可信流量。

### Task 4：质量统计结果表

目标：支撑区域、OLT、PON 口趋势、排名和日报。

产出：

- `area_quality_daily_summary`
- `olt_quality_daily_summary`
- `pon_quality_daily_summary`

实现策略：

- 从 `onu_quality_daily_detail` 和当前/每日特征表生成。
- 前端统计页只读 summary 表，不扫 raw/his。

### Task 5：基础异常候选

目标：生成 AIOps 可消费的可解释基础异常候选。

产出：

- `pon_quality_event`
- `onu_degradation_event`

实现策略：

- PON 口批量异常先按弱光数量、弱光比例、离线数量做规则。
- ONU 劣化先按最近 7 天与前 7 天均值下降、当前距离阈值余量做规则。
- 只输出候选和证据，不做复杂根因判断。

### Task 6：查询/API 层

目标：提供前端、小程序和 AIOps 读取的稳定接口。

优先级：

1. `GET /api/onu/{mac}/current`
2. `GET /api/onu/{mac}/power-trend?range=24h`
3. `GET /api/onu/{mac}/traffic-daily`
4. `GET /api/quality/onu-daily`
5. `GET /api/quality/summary`
6. `GET /api/collector/tasks`
7. `GET /api/olt/{id}/performance`

说明：当前仓库是 collector，不包含 Web API；API 应在现有后端项目实现，collector 负责提供稳定表和视图。

### Task 7：ClickHouse 试运行

目标：把长期趋势、历史明细和大范围统计从 MySQL 压力中剥离。

产出：

- 单节点 ClickHouse。
- 第一批表：`onu_optical_sample`、`onu_quality_daily_detail_ch`、`onu_traffic_daily_ch`、`olt_perf_sample`。
- collector ClickHouse 批量写入模块。
- 写失败 JSONL 补偿机制。

服务器建议：

- `JSCN-236` 继续运行 collector。
- ClickHouse 优先放在新增或较空闲服务器，不建议直接挤压 236。
- 如要正式进入该阶段，需要提供目标服务器 CPU、内存、磁盘、系统版本和网络连通性。

当前进展：

- `172.25.194.212` 已部署 ClickHouse `25.3.14.14`。
- 已创建 `go_collector_ch` 和第一批表。
- collector 已接入 `onu_optical_sample` 写入。
- 236 到 212 的 `8123` / `9000` 连通性已验证。

### Task 8：外部 ONU 写入降压

目标：降低每小时外部 ONU 大批量写 MySQL history 的压力。

产出：

- 外部 history 写入模式配置：`disabled`、`hourly`、`daily_snapshot`。
- MySQL 保留 latest，长历史转 ClickHouse。

实现策略：

- 第一阶段仍保留当前写法，先补查询和日报结果。
- 第二阶段再改写入模式，避免同时引入太多变量。

## 3. 当前可立即落地的第一批改造

第一批只做 schema 和文档，不碰生产进程：

1. 新增 `v_onu_current`。
2. 新增 `onu_quality_daily_detail`。
3. 新增 `onu_traffic_daily`。
4. 新增质量统计三张表。
5. 新增 `pon_quality_event`、`onu_degradation_event`。
6. 为 `collector_task_overview` 补充观测字段。

当前进展：

- phase1 MySQL schema 已在 236 `go_collector` 库执行。
- `v_onu_current`、`onu_quality_daily_detail`、`onu_traffic_daily`、`pon_quality_event`、`onu_degradation_event` 已创建。
- `collector_task_overview.blocked_reason` 等观测字段已创建。

对应 SQL：

- `sql/20260629_requirement_phase1_schema.sql`

执行前需要在生产库上确认：

- 是否接受新增视图和表。
- 是否要同时扩展 `olt_pon_business_info` 的导入批次字段。
- 是否在低峰窗口执行。

## 4. 需要用户后续提供的信息

进入 ClickHouse 或多服务器阶段前，需要补充：

- 可用服务器 IP、CPU、内存、磁盘类型和容量。
- 是否允许 collector 从 236 直连 ClickHouse。
- ClickHouse 是否需要高可用，还是先单节点试运行。
- 前端/API 项目仓库位置。
- 当前业务资料导入流程和导出格式要求。
