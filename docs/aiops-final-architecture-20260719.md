# AIOps 最终接入架构与运行决策（2026-07-19）

## 最终方案

保持两台服务器，不做全量合并：233 负责统一门户、登录、页面权限和 BFF；20 继续承载 AIOps API、Scheduler、QQ/NapCat、MySQL、ELK 与事件处理。MySQL 和 ELK 均不迁到 233。

| 节点 | CPU / 内存 / 磁盘（验收时） | 职责 |
|---|---|---|
| 233 | 8 核 / 31 GiB / 1.8 TiB | 统一网管前端、7001 API、平台账号与菜单权限、AIOps 签名代理 |
| 20 | 8 核 / 141 GiB / 系统盘 273 GiB + 数据盘 916 GiB | AIOps 应用与数据平面、MySQL、Elasticsearch、Logstash、Kibana、Scheduler、QQ |

20 当前可用内存约 133 GiB，数据盘使用约 1%；233 可用内存约 28 GiB。ELK 属于内存和 IO 密集服务，迁到 233 会把门户故障域与日志数据面合并，也不能消除 20（采集与 AIOps 服务仍需运行），收益很小、风险更大。因此保持现状是性能和运维复杂度之间更稳妥的方案。

## 页面与权限

- 智能运维：AIOps 运维看板、AIOps 运维中心、AI 问答、知识库。
- 运维中心子页：态势总览、分析历史、聚合事件、Syslog、Trap、规则配置、定时任务。
- AIOps 系统管理：管理总览、模型管理、运行设置、操作审计。
- AIOps 不做设备区域/组织数据过滤。系统管理角色或安播中心人员通过页面权限后可看全量 AIOps 内容；其他普通员工不显示入口，接口直连也拒绝。

## 数据流

```text
浏览器 -> 233:5772 统一前端 -> 233:7001 登录/权限/BFF
                                  |
                                  +-- HMAC 签名身份 -> 20:18080 AIOps API
                                                            |
                                                            +-- MySQL: 配置、任务、分析结果、审计
                                                            +-- Elasticsearch: Syslog/Trap/Events
                                                            +-- 模型网关: 分析与问答
20 Scheduler/QQ Adapter ------------------------------------+
```

## 生产修复与回滚

- `ai_findings.device_ip` 已从 `VARCHAR(64)` 扩为 `VARCHAR(512)`，原表 2152 行已备份到 `ai_findings_backup_20260719`；代码同时将身份摘要限制在 512 字符，完整内容仍保存在 `raw_finding`。
- 18080 用户进程报告目录为 `/home/yvesyuan/jscn-aiops-data/reports/ai_runs`，避免写入 root 容器目录失败。
- 233/20 本次文件备份：`/home/yvesyuan/deploy-backups/aiops-integration/20260719-101901/`。
- 233 原前端目录：`/var/www/NetAlert/frontend/dist/2026.old-20260719-101901`。

## 验收口径

- 前端 Vue/TypeScript 构建成功，AIOps Python 自动化测试 70 项通过。
- 管理角色 4 个入口可见；非安播中心普通用户入口不可见、接口为 403。
- 全局 24 小时数据在验收时约为 Syslog 2.28 万、Trap 117、聚合事件 9780+。
- 分析历史、任务、知识库、模型绑定接口返回 200；用途绑定模型 18 实际调用测试成功。
- 通过统一 BFF 发起的 4 小时真实分析 `22008b7b-2947-40ce-8b7a-fd9d159acef3` 成功完成，生成 20 项分析内容并写入持久化报告目录，可供看板时间轴直接切换。

## 2026-07-19 生产反馈闭环

- 运维看板历史结果改为独立轮播选择组件，页面根节点不再产生横向滚动；在 2048×1080、100% 缩放下验证 `document.scrollWidth == viewport width`。
- Finding 展示与原 AIOps 对齐为“研判结论、关键证据、建议动作、缺失数据”，证据和建议使用详情抽屉完整展示，移除无值置信度占位。
- 知识库恢复“导入管理”，支持故障报告、值班报修 Excel、运维文档三类上传；用户 API 上传目录为 `/home/yvesyuan/jscn-aiops-data/uploads/fault_kb`。
- 修复系统内置 `admin`（`super_admin`、`user_type=system`）被内部菜单标签误过滤的问题；精确账号验收确认驾驶舱、FTTH、HFC、智能运维与系统管理菜单全部返回。
- 12 小时生产任务验收运行 `db446efc-1733-41ea-aee2-7c0036c0ea69` 成功：模型 `deepseek-v4-pro`，4 次模型调用，20 项 Finding 成功入库，任务状态已由旧失败更新为成功。
