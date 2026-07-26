# 模块地图与命名

新项目组按独立部署边界拆分，而不是按语言拆分。每个仓库可独立构建、测试、发布、回滚；跨模块协议只在本仓库登记。

| 仓库 | 代码边界 | 数据边界 | 禁止混入 |
| --- | --- | --- | --- |
| `netops-collector` | `collector`、`collector-agent`、SNMP/调度/落库 | 236 MySQL、212 ClickHouse | Web、AIOps 业务代码 |
| `netops-portal-web` | Vue SPA | 无直连数据库 | 后端密钥、`dist` |
| `netops-platform-api` | Flask BFF、审计和集成脚本 | 233 `anbo_wx` | 前端构建产物、AIOps 内部实现 |
| `netops-radius-monitor` | 213 Radius 流量采集 | SQLite spool、212 ClickHouse | 原始报文和 spool 数据 |
| `netops-aiops` | 20 的 AIOps/ELK | AIOps MySQL、Elasticsearch | 原始告警报告、索引数据、`.env` |
| `netops-littleProgram` | 小程序、业务 API、迁移 | 小程序业务库 | 真实上传文件、用户凭据 |

所有仓库使用 `main` 作为稳定分支；发布采用不可变 tag，例如 `collector-v2026.07.26.1`。模块仓库需要在根 README 说明职责、设计、数据库、端口、安全、部署和验证方式。
