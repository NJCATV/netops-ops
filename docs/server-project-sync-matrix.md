# 服务器、项目与同步矩阵

更新时间：2026-07-27。此表区分 **受控源码副本** 与 **生产运行目录**：前者用于审计、构建和发布，后者可能包含运行配置或待审核改动，不能用 `git reset` 强制覆盖。

| 服务器 | 承载项目与职责 | 生产运行目录 | 本地受控仓库 | 服务器受控副本 | GitHub 仓库 | 当前同步结论 |
| --- | --- | --- | --- | --- | --- | --- |
| 233 `172.31.1.233` | 统一入口、门户前端、BFF、小程序业务后端 | `/srv/netops/netops-portal-web`；`/srv/netops/netops-littleProgram` | `netops-portal-web`、`netops-platform-api`、`netops-littleProgram` | `/home/yvesyuan/netops-staging/netops-ops` | `NJCATV/netops-portal-web`、`netops-platform-api`、`netops-littleProgram` | 入口为 `5772`，BFF 为本机 `7001`。本次已定向发布拓扑和日志修复；运行树保留两处受控文件改动，需在下一次完整前端发布时与 GitHub 提交合并，不能用重置覆盖。 |
| 236 `172.31.1.236` | Go 采集器、采集 Agent、采集 MySQL 与设备查询 | `/home/jscn123/PycharmProjects/go-collector` | `netops-collector` | `/home/jscn123/netops-staging/netops-collector` | `NJCATV/netops-collector` | 受控副本与 GitHub 一致；遗留运行目录保持原样，待采集服务正式切换后再更名。 |
| 20 `172.25.60.20` | AIOps、分析任务、ELK、Kibana | `/opt/jscn-aiops` | `netops-aiops` | `/home/yvesyuan/netops-staging/netops-aiops` | `NJCATV/netops-aiops` | 受控副本与 GitHub 一致；运行目录仍有未审核改动，禁止强制覆盖，需单独评审发布。 |
| 213 `172.25.194.213` | Radius 报文抓取、解析、spool 与落库 | `/opt/radius_monitor` | `netops-radius-monitor` | `/home/njcatv/netops-staging/netops-radius-monitor` | `NJCATV/netops-radius-monitor` | 受控副本与 GitHub 一致；运行目录为非 Git 目录，需在发布窗口纳入版本化目录。 |
| 212 `172.25.194.212` | ClickHouse 数据仓库与分析服务 | ClickHouse 服务（无业务应用源码目录） | `netops-ops` | `/home/njcatv/netops-staging/netops-ops` | `NJCATV/netops-ops` | 部署与安全脚本已受控；该节点不伪造应用仓库，只维护数据节点运行与端口守卫配置。 |

## 模块边界

| 模块 | 用途 | 主要数据存储 | 文档入口 |
| --- | --- | --- | --- |
| `netops-ops` | 总体架构、部署、拓扑和安全基线 | 无业务数据 | `README.md`、`docs/server-topology.md` |
| `netops-collector` | SNMP 采集、调度、采集批次与 Agent | 236 MySQL、212 ClickHouse | `docs/module-contract.md` |
| `netops-portal-web` | Vue 网管门户和可视化页面 | 不直接访问数据库 | `docs/module-contract.md` |
| `netops-platform-api` | 233 BFF、权限、审计、跨服务代理 | 233 业务库、236/212 查询 | `docs/module-contract.md` |
| `netops-radius-monitor` | Radius 抓包、解析和写入 | 213 SQLite spool、212 ClickHouse | `docs/module-contract.md` |
| `netops-aiops` | AIOps、规则、任务与日志检索 | 20 MySQL、Elasticsearch | `README.md`、`docs/` |
| `netops-littleProgram` | 小程序及其业务后端 | 233 小程序业务库 | `README.md`、`DATABASE_DESIGN.md` |

## 同步规则

1. 代码先进入对应模块仓库并通过构建/语法检查，再推送 GitHub `main`。
2. 服务器只同步同名的 `netops-staging/<module>` 受控副本；运行目录仅通过有回滚点的发布步骤更新。
3. `.env`、数据库导出、抓包文件、原始日志和用户凭据不进入 Git。
4. 每次运行态变更在 `netops-ops/docs/` 留下端口、安全和验证记录。
