# AIOps 接入南京安播智维平台实施总计划

更新时间：`2026-07-17`

## 0. 生产实测后的最终部署决策

本节覆盖本文后续章节中早期拟定的“把 AIOps API/MySQL 迁到 233”方案。
2026-07-17 通过 `JSCN-233`、`JSCN-20`、`JSCN-236` 实机盘点确认：

- 233：8 核、31 GiB 内存，负责统一前端、网管 API/BFF 和登录权限边界。
- 20：8 核、141 GiB 内存，保留 AIOps API、Scheduler、QQ/NapCat、MySQL、ELK 和采集 Worker。
- 236：40 核、125 GiB 内存，是网管现有 MySQL 节点；AIOps 库只有约 54.7 MiB，但当前账号没有创建独立 Schema 的权限。
- 网络只允许 233 主动访问 20；20 主动访问 233 超时。两台机器都可访问 236。

因此最终方案为：浏览器只访问 233，233 BFF 以 HMAC 签名身份单向调用
`http://172.25.60.20:18080`；AIOps 数据和计算继续留在 20。ELK 不迁移，MySQL
本次也不迁移。把 `jscn_aiops` 迁到 236 只能作为获得 DBA 权限后的独立优化，必须
保持独立 Schema，禁止把 AIOps 表直接混入 `go_collector`。

这个方案不增加服务器，避免 20→233 网络改造，也避免在 31 GiB 的 233 上叠加
ELK I/O 和 JVM 堆。生产切换证据见 `aiops-production-cutover-20260717.md`。

## 1. 目标状态

AIOps 不再作为独立 Web 系统面向用户。用户只访问南京安播智维平台，使用同一账号、同一组织范围、同一权限体系和同一套明暗主题。

最终运行边界：

| 节点 | 组件 | 说明 |
| --- | --- | --- |
| JSCN-233 | Nginx、统一 Vue 前端、网管 API、AIOps API、AI Scheduler、MySQL | 应用和控制平面 |
| JSCN-20 | Logstash、Elasticsearch、Kibana、事件聚合 Worker、QQ/NapCat 通道 | 日志接入和检索数据平面 |

MySQL 采用同一实例、独立 Schema：

- `anbo_wx`：平台用户、组织、角色、菜单和权限。
- `jscn_aiops`：模型、任务、规则、AI 分析、知识库元数据、聊天和审计。

## 2. 产品模块

统一前端新增以下路由：

| 路由 | 页面 | 权限键 |
| --- | --- | --- |
| `/aiops` | AIOps 总览 | `netops.aiops.view` |
| `/aiops/events` | 聚合事件 | `netops.aiops.events.view` |
| `/aiops/analysis` | AI 分析与历史 | `netops.aiops.analysis.view` |
| `/aiops/syslog` | Syslog 检索 | `netops.aiops.logs.view` |
| `/aiops/trap` | Trap 检索 | `netops.aiops.logs.view` |
| `/aiops/tasks` | AI 调度任务 | `netops.aiops.tasks.manage` |
| `/aiops/rules` | AI 分析规则 | `netops.aiops.rules.manage` |
| `/aiops/knowledge` | 故障知识库 | `netops.aiops.kb.manage` |
| `/aiops/models` | 模型与用途绑定 | `netops.aiops.models.manage` |
| `/ai-assistant` | 独立 AI 运维助手 | `netops.ai_chat.use` |
| `/aiops/audit` | 聊天、QQ 和操作审计 | `netops.aiops.audit.view` |

普通用户只看到总览、授权范围内的事件与 AI 助手。配置、模型、规则、任务和审计页面只向具备对应权限的管理员开放。

## 3. 统一身份设计

### 3.1 请求链路

1. 浏览器只向 `/wx/api/netops2026/*` 发送网管 Bearer JWT。
2. 网管 API 使用现有 `login_required` 校验 JWT、用户状态和组织。
3. `/aiops/*` BFF 路由把请求转发到 AIOps API。
4. BFF 使用共享密钥对用户身份、权限、组织范围、请求方法、路径和时间戳做 HMAC-SHA256 签名。
5. AIOps API 只接受有效且未过期的内部签名，不信任浏览器传入的身份头。

签名身份至少包含：

- `subject`：网管用户 ID。
- `username`、`display_name`。
- `role_code`、`user_type`。
- `org_id`、`org_name`。
- `regions`：允许查询的设备区域；`null` 表示全局范围，空数组表示无设备数据权限。
- `permissions`：AIOps 能力键集合。

### 3.2 AIOps 身份投影

AIOps `users` 表不再承担密码登录。新增：

- `identity_source`：`local` 或 `netops`。
- `external_subject`：网管用户 ID 字符串。
- `external_role_code`、`external_org_id`、`external_org_name`。
- `last_synced_at`。

请求首次到达时，AIOps 通过 `(identity_source, external_subject)` 查询或创建身份投影。聊天、分析反馈和审计表继续使用本地整数外键，因此历史关系无需重写；平台用户信息以每次请求携带的签名身份为准进行同步。

本地密码登录仅在迁移窗口保留，通过 `AIOPS_LOCAL_AUTH_ENABLED=false` 在正式切换时关闭。注册接口在正式环境永久关闭。

## 4. 数据权限

数据权限必须在 AIOps 后端和 Elasticsearch 查询层实施，不能只隐藏前端菜单。

- `regions is null`：全局查询。
- `regions == []`：返回空数据集，禁止退化成全局查询。
- 非空 `regions`：所有事件、Syslog、Trap、AI 上下文和工具查询附加区域过滤。
- AI 模型只接收已经过范围过滤的摘要和证据。
- 知识库文档默认全局；包含区域敏感数据的知识条目必须增加 `region_scope`。

## 5. 数据库迁移

1. 在 233 MySQL 创建独立 `jscn_aiops` Schema 和最小权限账号。
2. 在 20 执行一致性备份，记录每张表的行数和校验值。
3. 在备份副本上执行平台身份迁移 DDL。
4. 恢复到 233，运行只读验证。
5. 切换窗口暂停 AI Scheduler、聊天和配置写入。
6. 执行最终增量备份、恢复和校验。
7. 切换 233 AIOps API/Scheduler 数据库地址。
8. 20 的旧 MySQL 保持停止但不删除至少 7 天。

API Key 不进入前端、不进入 Git。模型供应商密钥后续应从数据库明文迁移到环境变量或独立密钥存储。

## 6. 前端与主题

AIOps 页面直接使用网管全局变量：`--bg`、`--card`、`--text`、`--muted`、`--line`、`--primary` 等。

- 浅色为默认主题。
- 深色由根节点 `data-theme="dark"` 控制。
- 不在组件内写死大面积 `#020617`、`#0f172a` 等黑色背景。
- 图表颜色、Tooltip、空状态、表格、抽屉和编辑器均必须在两种主题下验证。
- 主题选择继续使用 `netops2026_web_theme`，AIOps 不创建第二个主题配置。

## 7. 后端边界

233 AIOps API 负责：

- 页面查询接口。
- AI 分析发起、历史和反馈。
- 模型、规则、任务、知识库和聊天。
- 统一身份投影与审计。

20 数据服务负责：

- UDP Syslog/Trap 接入。
- 原始与结构化日志索引。
- 聚合事件 Worker。
- Kibana 管理查询。

233 通过受限网络访问 20 的 Elasticsearch 9200。9200 只允许 233 和管理地址；5601 只允许管理网；迁移完成后关闭 20 的 8080、5772、13306 对外访问。

## 8. 实施阶段与验收门槛

### 阶段 A：代码基线和安全前置

- 合并本地与 20 未提交的 AIOps 修改，形成可部署提交。
- 修复 233 的 NTP/时区错误。
- 备份 MySQL 和 Elasticsearch。
- 禁止浏览器保存 Base64 密码。

### 阶段 B：身份与 BFF

- 网管 BFF 转发和 HMAC 签名完成。
- AIOps 平台身份校验、投影和权限装饰器完成。
- 401、403、签名过期、篡改和区域空范围均有自动测试。

### 阶段 C：前端迁移

- 先迁独立 AI 助手，再迁总览、事件和 AI 分析。
- 再迁 Syslog/Trap、任务、规则、知识库、模型和审计。
- 移除 AIOps 独立登录、侧栏和用户管理页面。
- 所有页面完成浅色/深色和移动宽度验证。

### 阶段 D：MySQL 与应用迁移

- AIOps API 和 Scheduler 在 233 运行。
- MySQL 行数、关键表校验、聊天归属和任务配置一致。
- 20 在应用迁移后仍持续接收 UDP 日志且无时间断层。

### 阶段 E：生产验收

- 单点登录，无第二次登录和 AIOps Session Cookie。
- 普通用户、区域管理员、超级管理员权限矩阵通过。
- 区域用户无法通过 API 或 AI 工具取得范围外日志。
- 浅色和深色均无不可读文本、黑底残留或图表对比度问题。
- ES 单节点副本调整为 0，集群恢复绿色，并配置索引生命周期。
- 回退演练验证可通过 Nginx 和数据库配置恢复旧服务。

## 9. 回退原则

- 迁移过程中不删除 20 的原数据库、原前端和原 API。
- 数据切换采用短暂停写，不做不可控双写。
- 233 异常时可把 BFF 指回 20 原 API，并按最终差异备份反向恢复 MySQL。
- 观察期结束并完成备份恢复演练后，才下线旧服务。
