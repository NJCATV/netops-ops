# AIOps 生产接入与部署决策（2026-07-17）

## 结论

采用“233 统一门户与认证，20 保留完整 AIOps 服务和数据”的两节点方案：

| 节点 | 生产职责 | 决策理由 |
|---|---|---|
| JSCN-233 | `/2026` 统一前端、网管 API、AIOps BFF、菜单和角色权限 | 用户入口和身份边界统一；233→20 网络畅通 |
| JSCN-20 | AIOps API、Scheduler、QQ/NapCat、MySQL、Elasticsearch、Kibana、Logstash、事件 Worker | 141 GiB 内存，现有数据和采集链路均在本机 |
| JSCN-236 | 网管现有 MySQL（`go_collector`） | 暂不迁入 AIOps；待 DBA 创建独立 `jscn_aiops` Schema 后再评估 |

不把 ELK 迁到 233。AIOps MySQL 只有约 54.7 MiB，但迁库不会减少服务器数量，
还会引入额外切换风险；本次保持在 20。禁止与 `go_collector` 共用同一 Schema。

## 已上线内容

- 233 BFF：`/api/netops2026/aiops/*`，校验平台 JWT 后签名转发用户、角色、组织、区域和权限。
- 233 前端：AIOps 总览、事件、分析、Syslog/Trap、任务、规则、知识库、模型、设置、审计，以及独立 `/ai-assistant`。
- 主题：沿用平台变量，默认浅色并支持深色，不保留 AIOps 原黑底壳层。
- 20 API：`0.0.0.0:18080`，严格 90 秒 HMAC 验签，本地密码登录关闭。
- 数据库：执行 `20260717_platform_integration_v2` 增量迁移；无删表、无改名，幂等复验为空。
- 数据权限：AIOps 是全局运维数据集，不再按设备区域或用户组织过滤；页面入口权限是唯一访问边界。系统管理角色和安播中心人员可访问，非授权人员菜单不可见且直连接口返回 403。
- 自恢复：233 的 7001 后端和 20 的 18080 API 均有用户 crontab `@reboot`；20 scope sync 有 cron 和 flock 防重入。

## 验收证据

- AIOps 自动化测试：66 passed。
- Vue/TypeScript 生产构建成功；HTTPS 下 `index.html`、主 JS、主 CSS 均返回 200。
- 三角色：普通用户、组织管理员、超级管理员都可进入 AIOps/AI 助手；模型管理仅超级管理员 200，其余 403。
- AI 助手会话列表三角色均通过统一身份返回 200；审计仅超级管理员 200。
- 空区域身份：只要拥有 AIOps 页面权限，总览、历史分析与证据数据均按全局口径返回。
- 重放、过期、篡改签名均返回 401。
- AIOps API 数据库健康检查 200；运行日志无 Error/Traceback。

## 回滚点

- 233：`/home/yvesyuan/deploy-backups/aiops-integration/20260717-161200/`
- 20：`/opt/jscn-aiops/backups/20260717-161200/`
- 20 数据库备份：`jscn_aiops.sql.gz`，已通过 `gzip -t` 和 SHA-256 校验。
- 旧前端资源、旧 AIOps 8080 API、旧 MySQL 和 ELK 均未删除。

## 2026-07-19 完成项

1. 233 已启用 NTP，同步状态正常。
2. 20 的 Scheduler 与 QQ Adapter 已由管理员重启并保持 Up。
3. 任务写入开关 `aiops.task_mutations_enabled` 已开启，规则和定时任务可以从统一平台维护。
4. 新增原版风格的 AIOps 运维看板、历史结果横向时间轴、独立 AI 问答和知识库入口；模型、设置、审计归入独立的 AIOps 系统管理分组。
5. 统一驾驶舱已接入 24 小时 Syslog、Trap、聚合事件和最新 AI 结论摘要。
6. 修复 AI Finding 设备字段过长导致的落库失败，并将用户 API 报告目录切换到持久化可写路径。
