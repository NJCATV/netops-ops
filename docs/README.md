# 文档导航

从这里开始阅读本仓库，不需要先猜测服务在哪台服务器或哪一组代码负责。

## 仓库模块入口

| 范围 | 入口 | 说明 |
| --- | --- | --- |
| Go 采集程序 | [`cmd/`](../cmd/) | `collector`、`collector-agent` 两个可执行模块 |
| Go 领域实现 | [`internal/README.md`](../internal/README.md) | 采集、调度、落库、质差、性能与汇总 |
| 平台后端 | [`backend/README.md`](../backend/README.md) | `ops-platform-api` Flask BFF |
| 平台前端 | [`web/README.md`](../web/README.md) | `ops-platform` Vue SPA |
| 213 Radius | [`deploy/213/radius_monitor/README.md`](../deploy/213/radius_monitor/README.md) | 抓包、解析、spool 与 ClickHouse sink |
| 233 部署 | [`deploy/233/README.md`](../deploy/233/README.md) | Nginx、API、缓存预热、OA 迁移 |
| 安全策略 | [`deploy/security/README.md`](../deploy/security/README.md) | 20/213 防火墙守卫与 Fail2ban 模板 |
| 配置模板 | [`configs/README.md`](../configs/README.md) | 不含秘密的运行时样例 |
| 数据工具 | [`tools/README.md`](../tools/README.md) | 按需导入、核对和一次性工具 |
| SQL | [`sql/README.md`](../sql/README.md) | MySQL / ClickHouse 演进脚本 |
| 报告 | [`reports/README.md`](../reports/README.md) | 可复核的分析产物 |

| 文档 | 用途 |
| --- | --- |
| [平台架构与模块地图](platform-architecture-and-module-map.md) | 当前服务器、调用关系、模块职责、命名和安全基线 |
| [2026-07-26 交付与安全记录](platform-delivery-and-security-20260726.md) | 本轮功能、Radius、可观测性与端口收敛的事实记录 |
| [2026-07-26 安全运行态核验](security-runtime-audit-20260726.md) | 233/20/213/236 的实际防火墙、Docker 端口守卫与 Fail2ban 核验 |
| [Radius ClickHouse 迁移](radius-clickhouse-migration-20260726.md) | 213 Radius 采集、212 数据模型、回滚与验收 |
| [Radius 业务画像与流量优化](radius-profile-and-traffic-optimization-20260726.md) | Radius 业务/性能分析设计 |
| [Radius 与 ONU 六轮审计](radius-terminal-onu-six-pass-audit-20260726.md) | 终端关联及审计结论 |
| [AIOps 生产切换](aiops-production-cutover-20260717.md) | 20 AIOps 的发布和回滚记录 |
| [工程规范](engineering-standard.md) | 代码、数据库、发布与文档的共同约束 |
| [项目上下文](../PROJECT_CONTEXT.md) | 历史详细背景和运行基线 |

新功能、迁移、安全策略或生产故障完成后，应在 `docs/` 新增按日期命名的记录，
并在本表补充入口。不得写入密码、Token、生产 `.env` 或原始客户日志。
