# 服务器与调用拓扑

> 本文是当前代码和已验证部署资料的基线。生产变更后必须同步更新；未知项明确标记为“待核验”，不得用猜测补齐。端口与安全策略的运行态核验见 [2026-07-26 安全核验](security-runtime-audit-20260726.md)。

```text
浏览器 / 内网用户
        │ HTTPS :5772
        ▼
233 统一网管（Nginx / Vue / Flask BFF）
 ├── :18086 / :3339 ──► 236 采集与查询（Go Collector / Agent / MySQL）
 ├── :18080 ─────────► 20 AIOps（API / Scheduler / ELK）
 └── :8123 ──────────► 212 ClickHouse（历史分析）

NAS / BRAS 镜像流量 ── UDP 1812/1813/3799 ──► 213 Radius Monitor
213 Radius Monitor ── ClickHouse HTTP :8123 ──► 212
```

| 节点 | 地址 | 已知职责 | 关键接口与安全基线 |
| --- | --- | --- | --- |
| 233 | `172.31.1.233` | 对外统一入口、BFF、用户与审计 | 用户入口 `5772`；BFF `7001` 仅回环；MySQL `6603` 仅必要管理网段 |
| 236 | `172.31.1.236` | Go/旧采集、采集业务库 | Agent `18086`、MySQL `3339`；SSH `5333` 已接入 Fail2ban；**未发现主机入站白名单，待来源矩阵确认后收敛** |
| 20 | `172.25.60.20` | AIOps、MySQL、Elasticsearch、Kibana | `netops-aiops-port-guard.service` 已核验：API `18080/18190` 仅本机和 233；MySQL `13306`、Kibana `5601` 仅本机和 `172.31.0.0/16`；ES `9200` 仅本机和 Docker bridge；SSH `5332` 已接入 Fail2ban |
| 213 | `172.25.194.213` | Radius 报文镜像采集与解析 | `netops-radius-port-guard.service` 已核验：MySQL `3306` 仅本机和 `172.31.0.0/16`；监控 `18190` 仅本机和 233；SSH `5334` 已接入 Fail2ban |
| 212 | `172.25.194.212` | ClickHouse 历史分析与备份 | ClickHouse HTTP `8123`、Native `9000`；主机访问控制待本轮 SSH 核验 |

端口“允许来源”是策略描述，不包含口令；真实防火墙脚本位于 `deploy/security/`，每次变更需先验证 Docker 内网桥和服务间依赖后再收敛。
