# NJCATV 网络运维总控（netops-ops）

本仓库是网络运维项目组的**架构与发布事实来源**，不承载业务应用代码。它统一维护服务器拓扑、跨模块调用、端口与安全基线、部署模板和版本同步清单。

| 模块仓库 | 负责范围 | 主部署节点 |
| --- | --- | --- |
| `netops-collector` | Go 采集器、采集 Agent、采集数据演进 | 236 / 212 |
| `netops-portal-web` | 统一网管 Vue 前端 | 233 |
| `netops-platform-api` | 网管 BFF、权限、审计与跨服务代理 | 233 |
| `netops-radius-monitor` | Radius 抓包、解析、spool、落库 | 213 / 212 |
| `netops-aiops` | AIOps、ELK、规则和分析任务 | 20 |
| `netops-littleProgram` | 小程序及其业务后端 | 233 |

先阅读 [模块地图](docs/module-map.md)、[服务器与拓扑](docs/server-topology.md) 和 [同步约定](docs/sync-contract.md)。禁止提交密码、Token、真实 `.env`、客户数据、原始日志、数据库导出或构建产物。
