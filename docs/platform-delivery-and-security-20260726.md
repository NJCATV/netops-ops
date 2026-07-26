# 平台功能、基础设施与安全交付记录（2026-07-26）

## 范围与结论

本次交付覆盖 ONU 质差导出、采集批次可观测性、AIOps 分析质量、
超级管理员审计、Radius 接入、基础设施拓扑/服务日志，以及 20/213/236
的 SSH 和端口防护。所有功能入口均继续通过 233 的统一网管鉴权；运行
密码、Token、真实 `.env` 和客户原始日志未写入仓库。

## 功能变更

### ONU 与采集

- 修复 ONU 质差 Excel 导出失败，并将导出进度改为按实际工作量推进，避免
  起始固定百分比后长时间不变化。
- 采集监控增加以**采集批次**为行的历史记录：开始/结束时间、批次耗时、
  设备与采集次数、成功/失败、超长采集和最大单台耗时。
- 增加 ECharts 批次成功数趋势图与更长的查询范围，历史批次不再只显示单日。

### AIOps

- 复核 RADIUS 告警与 PPP 认证失败的因果关系：普通、低频认证失败不能直接
  作为 RADIUS 服务故障证据；报告需区分正常业务拒绝、异常增长和服务不可达。
- 分析设计扩展为可比较当前窗口、历史基线、持续问题和已恢复问题；建议动作
  需附证据、置信度和可验证的下一步，避免把相关性误写成根因。
- 独立审计报告保存在 `reports/aiops-audit-20260726/`，其数据来源、查询窗口、
  证据限制和待修订结论均在产物清单中记录。

### 审计与基础设施可观测性

- 新增仅超级管理员可见的系统审计与使用分析页，记录登录、功能调用、AIOps
  使用与高频功能；页面修复空白/500 错误、用户展示与卡片布局。
- 新增基础设施监控和动态服务调用拓扑：233 为统一入口，236 为采集，20 为
  AIOps，212 为 ClickHouse，213 为 Radius 抓包与落库节点。
- 拓扑节点和服务可点击查看资源、组件状态和**受控服务日志尾部**。日志接口
  只接受预置服务键，最多返回 200 行，不支持由请求指定任意服务器路径。
- 20/233/236/213 部署轻量监控探针；212 使用 ClickHouse 异步指标，不伪造主机
  日志。213 已验证 `radius-sniffer.service` journal 可被平台安全读取。

## Radius 接入与数据边界

- 213 的 RADIUS 抓包/解析继续由 Python 服务负责，采集结果单写 212
  ClickHouse；233 通过 BFF 提供 Radius 查询、趋势、风险、Accounting 和导出。
- 213 加入平台拓扑及资源/服务监控，涵盖抓包解析、UDP 抓包、MySQL、Redis、
  ClickHouse sink。
- Radius 详细迁移、数据模型、回滚和验收记录见：
  - `docs/radius-clickhouse-migration-20260726.md`
  - `docs/radius-profile-and-traffic-optimization-20260726.md`
  - `docs/radius-terminal-onu-six-pass-audit-20260726.md`

## 安全收敛

### 213 Radius 节点

部署 `netops-radius-port-guard.service`，仅管理 3306 和 18190，不改变默认
INPUT 策略、SSH 5334 或 RADIUS 镜像抓包。

| 端口 | 允许来源 | 说明 |
| --- | --- | --- |
| 3306 MySQL | 本机、`172.31.0.0/16` | 数据库访问白名单 |
| 18190 监控探针 | 本机、`172.31.1.233` | 仅统一平台拉取 |
| 5334 SSH | 保持现状 | 由 Fail2ban SSH jail 防爆破 |

Fail2ban 已安装并使用 systemd SSH journal：5 次失败/10 分钟，封禁 24 小时。

### 236 采集节点

Fail2ban 已运行，但原默认 jail 只使用 `ssh`/22 语义；已显式修正为真实 SSH
端口 5333，并使用同一失败阈值和封禁时长。

### 20 AIOps 节点

20 同时存在主机监听与 Docker 发布端口。因此防护同时写入 `INPUT` 和
`DOCKER-USER`；Docker MySQL 的宿主机 13306 在转发后为
`172.21.0.3:3306`，规则按后者匹配以避免 DNAT 绕过。

| 服务/端口 | 当前来源策略 |
| --- | --- |
| AIOps API 18080、监控 18190 | 仅本机和 233（`172.31.1.233`） |
| AIOps MySQL 13306 | 仅本机与 `172.31.0.0/16` |
| Kibana 5601 | 仅本机与 `172.31.0.0/16` |
| Elasticsearch 9200 | 仅本机和 AIOps Docker bridge，禁止外部来源 |
| 8080、18088、3000、3001、6099 | 仅本机和 AIOps Docker bridge `172.21.0.0/16` |
| SSH 5332 | 保持管理入口；由 Fail2ban 防爆破 |

以下端口暂不收紧，原因是其业务来源仍需完整盘点：

- UDP 10086/10087 是 SNMP Trap/Syslog 接收口，已观察到至少
  `172.25.131.3` 正在上报；完成所有设备来源清单后应改为精确白名单。
- Cockpit 9090 有现有运维会话；确认运维跳板来源后再限制。

验证结果：233 可以连接其被授权的 18080、18190、13306、5601；213 无法连接
20 的 18080、18190、13306、9200、8080、5601。首次上线时发现 Docker 内部
Kibana/应用访问 Elasticsearch/MySQL 也被拦截，已增加仅限 `172.21.0.0/16` 的
bridge 放行；来自 `172.31.3.226` 的 Kibana 浏览器请求已返回 `302 /spaces/enter`。
外部来源策略未放宽。AIOps API、Elasticsearch 和 MySQL 容器均健康。20 的防护
服务、213 的防护服务及 Fail2ban jail 均为 `enabled`/`active`。

### 版本化运维模板

实际部署脚本和 jail 模板同步保存在 `deploy/security/`。该目录是**无秘密**的
配置基线，便于审计、重建和代码评审；应用前仍须在目标环境验证端口、容器 IP
和真实业务来源。

## 验证

- Python：`python -m py_compile` 覆盖基础设施 BFF 与监控探针。
- Web：`npm run build` 通过 Vue 类型检查和 Vite 生产构建。
- 线上：233 BFF 路由重新加载；20/213/236 Fail2ban jail 可用；20/213 端口保护
  服务开机启用；213 Radius/MySQL/监控探针保持运行。

## 仓库边界

当前工作目录只有一个 Git 根目录，远端为
`git@github.com:NJCATV/go_collector.git`。没有 Git submodule，也没有嵌套 Git
仓库。它是一个单仓库（monorepo），同时管理 Go 采集器、Vue Web、Flask BFF、
Radius 部署源码、SQL、部署模板、报告和运维文档。

`web/ops-platform/dist*` 为构建产物，按 `.gitignore` 规则不提交；源文件、SQL、
部署模板、文档和需要保留的审计报告应提交。
