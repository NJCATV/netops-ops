# 模块代码与服务器同步状态（2026-07-27）

## 结论

所有已发现的应用源码均已按职责拆分到对应的 NetOps GitHub 仓库。生产运行目录不会被 Git 强制覆盖：每个尚未完成命名切换的节点都先建立无密钥的受控暂存副本，待发布窗口执行可回滚切换。

| 模块 | GitHub 主仓库 | 已核验的代码基线 | 服务器受控副本 | 生产运行状态 |
| --- | --- | --- | --- | --- |
| 网管前端 | `netops-portal-web` | `481bb8e` 为本次已部署基线 | 233 `/srv/netops/netops-portal-web` | 已部署；该目录正在由用户调整，后续不自动同步或覆盖 |
| 平台 API | `netops-platform-api` | `823efd6` | 233 `/srv/netops/netops-platform-api` | 已部署为 `netops-platform-api.service` |
| 小程序 | `netops-littleProgram` | `b855ac2` | 233 `/srv/netops/netops-littleProgram` | 已纳入统一目录；业务运行按原发布单元保留 |
| 采集 | `netops-collector` | `ca94c88`；与 236 旧仓 `e6c7c51` 核验 | 236 `/home/jscn123/netops-staging/netops-collector` | 原 `collector-agent` 仍从 `/home/jscn123/PycharmProjects/go-collector` 运行 |
| Radius 监控 | `netops-radius-monitor` | `6eab281` | 213 `/home/njcatv/netops-staging/netops-radius-monitor` | `radius-sniffer.service` 仍从 `/opt/radius_monitor` 运行 |
| AIOps | `netops-aiops` | `38b13cb` | 20 `/home/yvesyuan/netops-staging/netops-aiops` | Compose 仍从 `/opt/jscn-aiops` 运行 |
| 总控与部署资料 | `netops-ops` | 本次文档提交后更新 | 233 `/home/yvesyuan/netops-staging/netops-ops` | 非业务运行仓库 |

## 拆分边界

- `netops-collector` 仅保留 Go 采集器、Agent、调度、数据写入和 SQL；旧 `go_collector` 中的 `backend/`、`web/` 不再复制。
- `netops-platform-api` 仅负责统一 API、认证授权、审计与跨服务代理；`netops-portal-web` 仅负责 Vue 页面。
- `netops-radius-monitor` 仅负责 Radius 抓包、解析、spool、ClickHouse/MySQL 落库及其 Web 状态页。
- `netops-aiops` 仅负责 AIOps 规则、分析、ELK/任务与运维集成。

## 发布与回滚规则

1. 先在模块仓 `main` 完成审查、构建和无秘密配置检查。
2. 同步到节点的 `netops-staging/<module>`，比较 Git 提交和生产配置差异。
3. 仅在窗口内将 systemd/Compose/Nginx 指向正式的 `/srv/netops/<module>` 或等价规范目录；发布前保留原服务单元与目录作为回滚点。
4. 发布后记录提交号、健康检查、端口访问控制和服务状态。不得把真实 `.env`、日志、抓包、数据库导出或备份提交到 Git。

## 已知待办

- 236 的入站策略仍是默认开放；需先确认采集 Agent `18086`、MySQL `3339` 和管理来源矩阵后，建立主机防火墙白名单。
- 20 和 213 的端口守卫、233 的 UFW 与 Fail2ban 已核验；详细事实见 [安全运行审计](security-runtime-audit-20260726.md)。
- 212 为数据节点，尚需单独完成 SSH 与主机级访问审计，再决定是否建立部署暂存目录。
- 233 前端源码目录当前由用户直接调整；待用户确认后，再以其确认的提交作为下一次同步基线。
