# 平台架构与模块地图

> 当前基线：2026-07-26（Asia/Shanghai）
>
> 本文是“代码在哪、部署在哪、谁调用谁、安全策略是什么”的总览。详细变更见
> [文档导航](README.md) 和按日期归档的交付记录。

## 1. 单仓库边界

本仓库是 `NJCATV/go_collector`，采用 **monorepo** 管理。当前仅有一个 Git 根目录，
没有 Git submodule 或嵌套子仓库。

```text
go_collector/
├─ cmd/                         Go 可执行入口
├─ internal/                    Go 采集领域实现
├─ backend/ops-platform-api/    233 上嵌入 anbo_wx 的 Flask BFF
├─ web/ops-platform/            Vue 3 统一网管前端
├─ configs/                     无秘密的运行时配置样例
├─ tools/                       按需执行的数据导入与核对工具
├─ deploy/233/                  统一网管入口部署资料
├─ deploy/213/radius_monitor/   213 RADIUS 抓包、解析、落库源码
├─ deploy/security/             无秘密的防火墙与 Fail2ban 模板
├─ sql/                         MySQL / ClickHouse 迁移脚本
├─ docs/                        架构、交付、审计与运维资料
└─ reports/                     可复核的分析报告产物
```

构建产物（`dist*`）、运行配置、Token、密码、日志、数据库导出和客户表格不进入 Git。

## 2. 服务器与调用拓扑

```text
用户浏览器
    │ HTTPS
    ▼
233 统一网管（Vue / Nginx / Flask BFF）
    ├──► 236 采集与查询（Collector Agent、Go Collector、采集 MySQL）
    ├──► 20  AIOps（AIOps API、MySQL、Elasticsearch、Kibana、Logstash）
    └──► 212 ClickHouse（ONU/OLT/Radius 历史分析）

213 Radius 节点（镜像抓包、解析、spool） ───► 212 ClickHouse
```

| 节点 | 职责 | 由平台使用的关键接口 |
| --- | --- | --- |
| 233 `172.31.1.233` | 统一登录、权限、前端、BFF、审计 | 7001（仅本机）、对外 Nginx |
| 236 `172.31.1.236` | Go/旧采集、查询和采集主库 | 18086、3339 |
| 20 `172.25.60.20` | AIOps API、ELK、AIOps MySQL、QQ 适配 | 18080、13306、5601、Trap/Syslog |
| 212 `172.25.194.212` | ClickHouse 历史/分析数据 | 8123、9000 |
| 213 `172.25.194.213` | Radius UDP 抓包、解析、spool、落库 | 3306、18190、SSH 5334 |

## 3. 模块清单与命名

| 模块名 | 源码目录 | 部署节点 | 说明 |
| --- | --- | --- | --- |
| `collector` | `cmd/collector/` | 236 | Go 采集主进程 |
| `collector-agent` | `cmd/collector-agent/` | 236 | 向 233 提供采集健康与统计接口 |
| `ops-platform-api` | `backend/ops-platform-api/` | 233 | `netops2026` Flask BFF、权限、审计、基础设施接口 |
| `ops-platform-web` | `web/ops-platform/` | 233 | Vue 3 统一网管 SPA |
| `radius-monitor` | `deploy/213/radius_monitor/` | 213 | RADIUS 抓包、解析、SQLite spool、ClickHouse sink |
| `security-guards` | `deploy/security/` | 20 / 213 / 236 | 端口白名单和 Fail2ban 可复现模板 |
| `schema-migrations` | `sql/` | 236 / 212 / 233 按需 | 数据库结构、索引和数据迁移 |

目录名保持稳定，不为“好看”改动生产路径。新增项目使用 `kebab-case`；可执行程序与
目录同名；部署资料放在 `deploy/<server-or-domain>/`；文档使用
`<topic>-YYYYMMDD.md`。

## 4. 安全基线

### SSH 防爆破

233、236、20、213 均使用 Fail2ban SSH jail：10 分钟内 5 次失败，封禁 24 小时。
实际 SSH 端口分别为 5333、5333、5332、5334。模板位于
`deploy/security/fail2ban/`。

### 213 Radius

- 3306：本机和 `172.31.0.0/16`；
- 18190：本机和 233；
- SSH 5334 与 UDP 镜像抓包不由端口收敛脚本修改。

### 20 AIOps

- 18080、18190：仅本机和 233；
- 13306 MySQL、5601 Kibana：仅本机和 `172.31.0.0/16`；
- 9200 Elasticsearch：仅本机和 AIOps Docker bridge，禁止外部来源；
- 8080、18088、3000、3001、6099：仅本机和 AIOps Docker bridge；
- UDP 10086/10087（Trap/Syslog）及 Cockpit 9090 需在设备/运维来源完整盘点后再
  收敛，当前不可凭空关闭。

20 同时维护 `INPUT` 和 `DOCKER-USER`：Docker MySQL 的外部 13306 在转发后是
`172.21.0.3:3306`，因此必须匹配后者，详见 `deploy/security/README.md`。

## 5. 可观测性与已知事项

- 基础设施页面仅超级管理员可见；可查看节点资源、服务状态和受控日志尾部。
- 212 无主机日志探针，页面只展示 ClickHouse 指标，不伪造系统日志。
- 2026-07-26 首次收紧时遗漏了 Kibana/应用容器访问 Elasticsearch/MySQL 的 Docker
  bridge 放行，造成 Kibana 超时；已补回仅 `172.21.0.0/16` 的内部放行并验证浏览器
  请求返回 `302 /spaces/enter`。若后续仍有 ES 超时，再按 ES/Kibana 性能故障处理，
  不应为了排障放宽外部来源策略。

## 6. 日常检查

```bash
# 代码
go test ./...
python -m py_compile backend/ops-platform-api/ops_platform_api.py
cd web/ops-platform && npm run build

# 20 / 213 防火墙服务
systemctl status netops-aiops-port-guard.service
systemctl status netops-radius-port-guard.service
fail2ban-client status sshd
```

具体发布、回滚、数据迁移与验收命令以模块 README 和日期文档为准。
