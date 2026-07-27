# 生产安全运行态核验（2026-07-26）

本文是对生产主机的**只读运行态核验**，用于纠正“只根据 UFW 状态判断是否有防火墙”的误解。所有结论均来自当日的 `systemctl`、`fail2ban-client`、`ufw`、`nft`、`iptables` 和监听端口检查；不包含密码、Token 或运行时环境变量。

## 结论摘要

| 节点 | SSH 防护 | 端口访问控制实现 | 结论 |
| --- | --- | --- | --- |
| 233 | `fail2ban` 已启用 | UFW（默认拒绝入站） | 已核验；平台入口和管理端口边界清晰 |
| 20 | `fail2ban` 已启用 | `netops-aiops-port-guard.service`，同时保护 `INPUT` 与 Docker `DOCKER-USER` | 已核验；UFW 未启用是设计选择，不代表端口裸露 |
| 213 | `fail2ban` 已启用 | `netops-radius-port-guard.service` 写入 nftables/iptables | 已核验；UFW 未启用是设计选择，不代表端口裸露 |
| 236 | `fail2ban` 已启用 | 未发现 UFW、nftables 或 iptables 入站白名单 | 风险项：需先确认全部调用来源后实施独立白名单变更 |
| 212 | `fail2ban` 已启用 | `netops-clickhouse-port-guard.service` | 已于 2026-07-27 部署并双向验证；保留 ClickHouse 本机监听设计，但以主机规则限制来源 |

## 233：统一入口与 BFF

- `netops-platform-api.service` 为 `active`、`enabled`；旧 `zhiwei-api.service` 已停止。
- 公网/内网统一入口为 TLS `5772/tcp`；`7001/tcp` 仅监听 `127.0.0.1`。
- UFW 已启用，默认拒绝入站：`5333/tcp`（SSH）与 `6603/tcp`（MySQL 管理）仅允许 `172.31.0.0/16`；`5772/tcp` 为统一浏览器入口。
- `fail2ban` 的 `sshd` jail 已启用。`18190/tcp` 虽有服务监听，但并不等同于公开放通，应以 UFW 规则和实际探针来源为准。

## 20：AIOps 与 Docker 数据面

`netops-aiops-port-guard.service` 已 `enabled`，并在 Docker 启动后执行。其目的是弥补“Docker 发布端口绕过单纯 INPUT 规则”的常见风险：

- `18080/tcp`（AIOps BFF API）与 `18190/tcp`（主机探针）仅允许本机和 `172.31.1.233`。
- MySQL 主机映射 `13306/tcp` 仅允许本机和 `172.31.0.0/16`；对应 Docker 容器目的地址的规则位于 `DOCKER-USER`。
- Kibana `5601/tcp` 仅允许 `172.31.0.0/16`；这解释了非该网段客户端不能直接打开 `http://172.25.60.20:5601/` 的现象。
- Elasticsearch `9200/tcp` 仅允许本机和 AIOps Docker bridge；其余对外入口及桥接内部服务由 `DOCKER-USER` 明确拒绝。
- UFW 为 inactive，但 `iptables` 中带 `netops-aiops-*` 标签的规则和 `DOCKER-USER` 规则是当前生效的控制层；不得在未同步 Docker 规则的情况下用 UFW 替换它们。

## 213：Radius 抓包与数据库

`netops-radius-port-guard.service` 已 `enabled`，以 nftables/iptables 规则约束监听在全网卡的服务：

- `3306/tcp` 仅允许本机和 `172.31.0.0/16`，供 233/236 等受控业务网段访问。
- `18190/tcp` 仅允许本机和 `172.31.1.233`，供平台基础设施探针访问。
- SSH 为 `5334/tcp`，`fail2ban` 的 `sshd` jail 已启用。
- Radius 镜像抓取属于被动采集路径；NAS/BRAS 的 UDP 报文关系见 `server-topology.md`，不要把它误写成浏览器或数据库入口。

## 212：ClickHouse 数据节点审计与收敛结果（2026-07-27）

- ClickHouse `25.3.14.14` 正常运行，业务库为 `go_collector_ch` 与 `radius_monitor_ch`；无本机应用 Git 仓库。
- `8123`、`9000`、`9004`、`9005`、`9009` 仍由 ClickHouse 监听在 `0.0.0.0`；这不是对外开放策略。持久化的 `netops-clickhouse-port-guard.service` 已先允许、后丢弃，且已设置为开机启用。
- 用户层已限制：`go_collector` 仅 233/236，`radius_reader` 仅 233，`radius_writer` 仅 213；这是数据库认证边界，不能替代主机网络边界。
- 已确认无外部 ClickHouse 集群/副本；236 采集器通过 HTTP `8123`，233 查询、213 Radius 写入均通过 `8123`。
- `8123/tcp` 仅允许 `172.31.1.233`、`172.31.1.236` 和 `172.25.194.213`；本机 `127.0.0.1` 仍可访问。已分别从 233、236、213 验证可达，从 20 验证被拒。
- SSH `5334/tcp` 仅允许回环和 `172.31.0.0/16`；`9000/9004/9005/9009` 仅允许回环，所有其他 IPv4 来源明确丢弃。
- `fail2ban` 的 `sshd` jail 已使用 SSH 端口 `5334`、systemd 日志后端、10 分钟窗口内 5 次失败、封禁 24 小时；正常 jail 状态已核验。
- 控制仓库位于 `/home/njcatv/netops-staging/netops-ops`，已记录与 GitHub `main` 相同的安全策略提交。此节点没有业务应用源码，不应为了目录一致性虚构应用仓库。

## 236：待执行的收敛事项

236 目前监听 `5333`、`18086`、`3339` 和 `18190`，且仅确认到 Fail2ban；未发现持久化的主机入站白名单。由于它承载采集与旧业务 API，直接启用“默认拒绝”可能影响设备采集、平台查询或历史业务。

在实施前必须形成并确认来源矩阵：

1. `5333/tcp`：管理网段与跳板地址；
2. `18086/tcp`、`3339/tcp`：233 BFF、必要的管理/批处理节点；
3. `18190/tcp`：233 平台探针；
4. SNMP/采集所需的出站权限不应被入站收敛误伤。

确认后应以独立变更部署 `netops-collector-port-guard.service`，先保留当前 SSH 会话、进行允许/拒绝双向测试，再固化规则。

## 日常复核命令

```bash
systemctl is-active fail2ban
fail2ban-client status sshd
systemctl is-active netops-aiops-port-guard.service       # 20
systemctl is-active netops-radius-port-guard.service      # 213
iptables -S
iptables -S DOCKER-USER                                   # 20
nft list ruleset                                          # 213
ufw status verbose                                        # 233
```

变更后还必须从一个允许来源和一个不允许来源分别验证，不允许只以“端口正在监听”或“UFW inactive”得出安全结论。
