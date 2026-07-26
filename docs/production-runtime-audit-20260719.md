# 生产运行与备份核查记录（2026-07-19）

## 1. 核查范围

| 节点 | 核查方式 | 覆盖内容 |
| --- | --- | --- |
| 233 | SSH `JSCN-233` | 服务、进程、端口、Nginx、Cron、代码目录 |
| 236 | SSH `JSCN-236` | 新旧采集、API、端口、Git、ClickHouse 连通性、备份目录权限 |
| 212 | 236 通过 ClickHouse HTTP 查询 | ClickHouse 版本、表数、采样行数和最新时间 |
| 20 | SSH `JSCN-20` | AIOps Scheduler、MySQL、模型、Elasticsearch、QQ Adapter/NapCat |

212 的 SSH 端口 `172.25.194.212:5334` 可达，但当前工作机及 236 普通账号没有 212 运维私钥；因此本次未直接读取 212 的 root Cron 和备份目录，而是通过 ClickHouse 业务账号验证数据面。备份任务的完整结果仍应由 root 按 README 的日常检查命令复核。

## 2. 233 核查结果

| 项目 | 核查结果 | 结论/动作 |
| --- | --- | --- |
| 系统时区 | UTC | 北京时间任务需换算为 UTC Cron |
| Nginx 5772 | 正常监听 | 保留旧版、新版和 `/wx/api/` 入口 |
| `anbo_wx` 7001 | systemd 托管 Gunicorn，4 Worker，仅绑定 `127.0.0.1` | 已完成正式切换 |
| `zhiwei-api.service` | active、enabled、`NRestarts=0` | 2026-07-19 04:44:23 UTC 接管 |
| Gunicorn 配置 | `--check-config` 通过 | 已正式接管 |
| `/2026/` SPA location | 已安装，未知子路由 HTTP 200 | 内容与新版 `index.html` 一致 |
| 旧版 newalertadmin/Celery | 正常 | 切换脚本不触碰 |
| MySQL 备份 Cron | `/etc/cron.d/db_backup_233`：`15 18 * * *` | 与北京时间 02:15 一致 |
| Git 工作树 | 服务器目录有历史部署改动和备份文件 | GitHub 仓库作为源，服务器仅作部署目标 |

## 3. 236 核查结果

| 项目 | 状态 | 备注 |
| --- | --- | --- |
| `newalert.service` | active | 旧版采集，必须保留 |
| `newalertapi.service` | active | Gunicorn 10086 |
| Collector Agent | 运行中 | 监听 18086 |
| Go Collector | 生产数据持续更新 | ClickHouse 最新采样已验证 |
| repair_records | 运行中 | Python 可执行文件已删除，重启有风险 |
| MySQL | 3339，全部网卡 | 依赖上层网络隔离 |
| Redis | 6379/6380 回环 | 正常 |
| Nginx 12345 | 已知 502 | 不属于本次 AIOps/新版发布范围 |
| UFW | 普通账号不可直接读取；既有核查为未启用 | 启用前必须完成端口白名单设计 |
| Git | `e6c7c51`，工作树干净 | 与本地及 GitHub 基线一致 |
| ClickHouse 异机目录 | `/var/backups/clickhouse-212`，`backup212:dbbackup`，750 | 普通采集账号不能列目录，权限隔离正确 |

## 4. 212/ClickHouse 核查结果

| 指标 | 结果 |
| --- | --- |
| HTTP 查询 | 236 → 212 返回 200 |
| ClickHouse 版本 | 25.3.14.14 |
| `go_collector_ch` 表数 | 7 |
| `onu_optical_sample` 行数 | 120,752,661 |
| 最早采样 | 2025-08-24 14:06:40 |
| 最新采样 | 2026-07-19 12:10:14 |

## 5. 20/AIOps 核查结果

| 项目 | 结果 |
| --- | --- |
| Scheduler | 2026-07-19 03:52:26 UTC 启动，晚于最终代码更新时间 |
| 数据面预检 | shared secret、Elasticsearch、API 身份、QQ 身份全部通过 |
| Elasticsearch | 单节点 yellow、无 timeout；当前可用 |
| 定时任务 | 12 小时全局任务成功，下一次 `2026-07-19 15:21:54 UTC` |
| 最新分析 | `deepseek-v4-pro`，4 次 LLM 调用，242,165 tokens，成功 |
| AIOps MySQL | 147 次运行、2,192 条 Findings、17 个模型、9 个用途绑定 |
| QQ Adapter | `/health` 200 |
| NapCat | 登录成功，账号“安播运维助手” |

## 6. 正式切换结果与回滚

| 项目 | 路径 |
| --- | --- |
| 已执行安装脚本 | `/home/yvesyuan/deploy/zhiwei-production-20260719/install-zhiwei-production.sh` |
| systemd 源文件 | `deploy/233/zhiwei-api.service` |
| Nginx 片段 | `deploy/233/nginx-2026-location.conf` |
| 本次自动备份目录 | `/var/backups/zhiwei-production/20260719T044422Z/` |

安装脚本仅在确认 7001 进程工作目录为 `anbo_wx/backend` 且命令包含 `run.py` 时才终止临时进程。任一步骤失败时会恢复 Nginx、用户 crontab，并重新启动原临时 API。

切换后验收：

| 验收项 | 结果 |
| --- | --- |
| systemd | active + enabled，主 PID 523758，零重启 |
| 监听地址 | `127.0.0.1:7001` |
| 旧 `@reboot` 启动项 | 已删除 |
| Nginx 配置检查 | 通过 |
| `/2026/nonexistent-route` | HTTP 200，返回新版首页 |
| admin 导航 | HTTP 200，21 个菜单，必需菜单齐全 |
| AIOps Overview | HTTP 200 |
| 旧版 newalertadmin | `newalertgunicorn.service` active |
| 旧版 Celery | `alertcelery.service` active |

## 7. 后续风险清单

| 优先级 | 风险 | 建议 |
| --- | --- | --- |
| 高 | 236 未启用主机防火墙且多个端口绑定全部网卡 | 先采集访问源清单，再分阶段启用 UFW |
| 高 | repair_records 虚拟环境文件已删除 | 维护窗口前重建环境和 systemd 单元 |
| 中 | 233 `anbo@%` 和 236 `admin_yves@%` 权限过大 | 创建最小权限应用账号并轮换 |
| 中 | 212 运维密钥未在当前受控工作机配置 | 建立只读审计账号或标准跳板访问流程 |
| 中 | Elasticsearch 单节点 yellow | 后续增加副本节点或把副本数调整为单节点策略 |
| 低 | `alertcelery.service` 存在 section 外配置和过时 syslog 输出警告 | 当前服务正常；在旧版独立维护窗口修正 unit，不与新版发布混改 |
| 低 | 236 Nginx 12345 返回 502 | 明确是否仍有业务依赖后单独修复或下线 |
