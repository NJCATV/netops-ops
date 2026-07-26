# 南京安播智维平台：项目全景与后续工作起点

> 文档定位：本文件是后续开发、排障、发布和新会话的统一起点。
> 最后整理：2026-07-20（Asia/Shanghai）。
> 当前 GitHub 基线：`NJCATV/go_collector` `main`，提交 `6df6119`。
> 信息来源：仓库代码与正式文档、历史会话交接材料、GitHub，以及 2026-07-20 对 233、236、20 和数据库链路的只读核验。
> 安全边界：本文记录服务器、端口、目录、库名和运行方式，但不记录密码、Token、共享密钥或生产运行配置正文。

## 1. 一句话认识项目

`go_collector` 已从单一 Go SNMP 采集器发展为“南京安播智维平台”的主仓库。当前单仓库同时维护：

- OLT、ONU、CMTS 的 Go 采集器和采集代理；
- Vue 3 新版网管前端；
- 嵌入 `anbo_wx` 的 Flask 网管 API 与权限层；
- AIOps 的统一入口、身份投影和 BFF；
- MySQL、ClickHouse 表结构和数据治理脚本；
- 233 生产部署、Nginx、systemd、备份和验收材料。

平台已经投入生产。当前阶段的主要任务不再是“从零搭建”，而是持续完善数据口径、权限回归、查询性能、运行标准化、安全收敛和可恢复性。

## 2. 当前总体架构

```text
浏览器 / 微信端
       |
       v
233:5772 Nginx
       |
       +-- /                 新版 Vue 网管
       +-- /2025/            旧版网管
       +-- /api/             旧版 newalertadmin
       +-- /wx/api/          新版 anbo_wx / netops2026 API -> 127.0.0.1:7001
       +-- /dify/            172.25.60.66:18088
       |
       +---> 236:18086 Collector Agent / 236:3339 MySQL
       |
       +---> 20:18080 AIOps API（HMAC 服务身份）
       |           +-- AIOps MySQL
       |           +-- Elasticsearch / Kibana
       |           +-- Scheduler / QQ Adapter / NapCat
       |
       +---> 212:8123 ClickHouse HTTP

236 Go Collector -----------------------> 236 MySQL（当前状态、业务数据）
             \--------------------------> 212 ClickHouse（历史采样、趋势）
```

架构原则：

1. 233 负责统一入口、账号、组织、菜单、权限和 BFF，不承载高负载日志检索。
2. 236 负责新旧采集与采集主数据；新版发布不得停止旧版采集。
3. 20 保留 AIOps 数据面，避免 Elasticsearch 和 AI 任务挤占 233。
4. 212 负责 ClickHouse 历史分析和集中备份落地。
5. MySQL 当前状态与 ClickHouse 历史数据职责分离；ClickHouse 写入失败不应阻断 MySQL 主写。

## 3. 产品范围与主要功能

| 一级范围 | 页面或能力 | 当前说明 |
| --- | --- | --- |
| 总览 | 统一驾驶舱 | 接入设备、采集健康、风险、链路、趋势、区域覆盖和平台指标 |
| FTTH | 单台 ONU 查询 | 按 MAC、ONU 标识、OLT 或地址查询，展示设备、端口、在线状态、光功率和业务信息 |
| FTTH | ONU 质差管理 | 日期/规则/区域/OLT 筛选，趋势、历史、端口和 OLT 聚合，支持 Excel 导出 |
| FTTH | OLT 性能看板 | OLT/板卡 CPU、内存、采集时间、端口状态、趋势和设备详情 |
| HFC | CM MAC 查询 | 当前以 MAC 查询为主，交互参考单台 ONU 查询 |
| HFC | CMTS 设备管理 | CMTS 设备、筛选和组织范围管理 |
| 采集监控 | 采集概览、任务、设备、历史 | 展示采集成功/失败、任务状态和设备明细 |
| 智能运维 | AIOps 运维看板 | 分析时间线、Findings、证据、建议动作和手动分析 |
| 智能运维 | AIOps 运维中心 | 分析历史、Events、Syslog、Trap、规则和定时任务 |
| 智能运维 | AI 问答、知识库 | 统一身份问答；报告、报修表和运维文档导入 |
| 系统管理 | 用户、组织、权限、设备组织 | OA 主数据、角色、菜单和服务端数据范围 |
| 系统管理 | AIOps 系统管理 | 模型、用途绑定、运行设置和审计日志 |

## 4. 访问入口与身份体系

### 4.1 访问入口

| 入口 | 用途 | 当前约束 |
| --- | --- | --- |
| `https://anbo.njcatv.net:5772/` | 新版正式入口 | 根路径独立 SPA 回退 |
| `https://172.31.1.233:5772/` | 新版内网入口 | 护网或内网场景使用 |
| `https://anbo.njcatv.net:5772/2025/` | 旧版入口 | 计划保留至 12 月 31 日 |
| `/2026/` | 新版历史路径 | 当前 301 跳转到 `/` |
| `/wx/api/` | 新版 API | Nginx 转发至 233 的 `127.0.0.1:7001` |
| `/api/` | 旧版 API | 必须与新版隔离保留 |

### 4.2 用户与登录

| 项目 | 当前规则 |
| --- | --- |
| 用户主数据 | OA 人员主数据为主，独立系统管理员作为保底账号 |
| 可用登录名 | OA 用户名、手机号、已绑定 OSS 账号 |
| 初始密码 | `Jscn@` + 手机号后四位；首次登录提醒修改，可暂时跳过 |
| OA 用户基线 | 1,641 人 |
| 平台账号基线 | 1,642 个，含 1 个保底系统管理员 |
| 保留 OSS 信息 | 455 人 |
| 最终人工提权 | 8 名 OA 用户，其余 1,633 名为普通用户 |
| 特殊冲突 | OA 与 OSS 登录名可能同名；后端逐候选校验密码，仅唯一匹配时签发 JWT |

### 4.3 权限边界

- 普通网管数据必须由服务端按用户组织、子组织和设备区域约束；前端筛选不能代替服务端授权。
- 区域用户只能看到授权区域；总部、安播中心等全域组织映射全部 11 个设备区域。
- 省 AI 门户游客不授予设备区域。
- AIOps 是独立权限模型：有 AIOps 页面权限的用户查看全量 AIOps 数据，不按设备区域或组织过滤。
- 停用账号或未授权账号不显示相应菜单，接口直连应返回 401/403。

## 5. 服务器清单与运行信息

### 5.1 233：统一 Web/API 应用服务器

| 项目 | 当前信息 |
| --- | --- |
| IP / SSH 别名 | `172.31.1.233` / `JSCN-233` |
| 主机名 | `anbo233` |
| 角色 | Nginx、新旧 Web/API、账号组织权限、AIOps BFF、Redis、应用 MySQL |
| 新版后端目录 | `/home/yvesyuan/PycharmProjects/anbo_wx/backend` |
| 新版路由文件 | `/home/yvesyuan/PycharmProjects/anbo_wx/backend/app/routes/netops2026.py` |
| 新版 API 服务 | `zhiwei-api.service`，Gunicorn 4 workers，`127.0.0.1:7001` |
| 新版前端目录 | `/var/www/NetAlert/frontend/dist`；`dist/2026` 为历史部署路径 |
| 旧版前端 | `/var/www/NetAlert/frontend/dist/2025` 或切换备份后的旧版目录 |
| 旧版服务 | `newalertgunicorn.service`、`alertcelery.service` |
| Redis | `127.0.0.1:6379` |
| MySQL | `0.0.0.0:6603`，通过网络和账号共同限制 |
| 质差缓存 | `zhiwei-quality-cache.timer`，约每 4 分钟预热 |

2026-07-20 只读核验：

- `zhiwei-api`、`newalertgunicorn`、`alertcelery`、Nginx、MySQL、Redis、质差缓存定时器均为 `active`。
- `zhiwei-api` 自 2026-07-19 04:44:23 UTC 启动，`NRestarts=0`。
- `/` 和 `/2025/` 返回 200，`/2026/` 返回 301，`/wx/api/health` 返回 200。
- 7001 仅绑定回环地址；5772 和 6603 监听全部网卡。

### 5.2 236：采集与数据服务器

| 项目 | 当前信息 |
| --- | --- |
| IP / SSH 别名 | `172.31.1.236` / `JSCN-236` |
| 主机名 | `anbo` |
| 仓库目录 | `/home/jscn123/PycharmProjects/go-collector` |
| 新版采集器 | `./bin/collector`，读取 `configs/runtime.official.json` |
| 采集代理 | `./bin/collector-agent`，监听 `0.0.0.0:18086` |
| 旧版采集 | `newalert.service`，必须保留 |
| 旧版 API | `newalertapi.service`，Gunicorn `0.0.0.0:10086` |
| MySQL | `0.0.0.0:3339` |
| Redis | `127.0.0.1:6379/6380` |
| repair_records | `0.0.0.0:5000` |

生产 Go Collector 启动参数基线：

```bash
./bin/collector \
  -config ./configs/runtime.official.json \
  -data-dir ./data-official-20260415-nightb \
  -log-dir ./logs-official-20260415-nightb \
  -log-level info \
  -instance-lock ./run/collector.lock
```

2026-07-20 只读核验：

- 新旧采集服务和 MySQL 正常；Collector Agent `/health` 返回 `ok`。
- Go Collector 与 Collector Agent 仍是手工进程，Collector 通过 `screen` 运行，尚未标准化为 systemd。
- `repair_records` 进程仍在运行，但历史核查发现其虚拟环境文件已删除，重启存在风险。
- 3339、5333、10086、18086、5000 等端口绑定全部网卡；主机防火墙收敛仍是高优先级风险。
- 服务器仓库位于 `e6c7c51`，工作树干净；相对 GitHub `main` 少 13 个平台类提交。之后的提交没有修改 Go Collector 源码，因此当前采集二进制不因该差异缺少采集功能，但仓库镜像应择机同步。

### 5.3 20：AIOps 数据与分析服务器

| 项目 | 当前信息 |
| --- | --- |
| IP / SSH 别名 | `172.25.60.20` / `JSCN-20` |
| 主机名 | `aiServer20` |
| 部署目录 | `/opt/jscn-aiops/deploy` |
| AIOps API | `0.0.0.0:18080`，由 233 使用共享密钥签名访问 |
| 原版本地入口 | `127.0.0.1:5772`，不再提供远程弱登录入口 |
| QQ Adapter | `0.0.0.0:18088` |
| Elasticsearch | `0.0.0.0:9200` |
| Kibana | `0.0.0.0:5601` |
| 容器 MySQL | `0.0.0.0:13306` |

主要组件包括 AIOps API、Web、MySQL、Elasticsearch、Kibana、Scheduler、QQ Adapter 和 NapCat。233 只做统一身份与代理，不把 AIOps MySQL/ELK 迁入 233。

2026-07-20 只读核验：

- 18080、18088、9200、5601、13306 等端口仍在监听。
- Elasticsearch 可响应，单节点状态为 `yellow`，382 个主分片正常、208 个副本分片未分配。
- 当前账号无 Docker daemon 读取权限，因此容器级状态以 2026-07-19 验收和进程/端口核验为准。

### 5.4 212：ClickHouse 与集中备份服务器

| 项目 | 当前信息 |
| --- | --- |
| IP | `172.25.194.212` |
| 角色 | ClickHouse 主库、233/236 MySQL 集中备份落地点 |
| HTTP / Native | `8123` / `9000` |
| 数据库 | `go_collector_ch` |
| 版本 | `25.3.14.14` |
| 表数 | 7 |
| SSH 状态 | 当前工作机没有 `JSCN-212` SSH 别名；通过 233/236 的受控配置访问数据库 |

2026-07-20 11:26 只读核验：

- `onu_optical_sample` 活跃分区约 120,760,376 行。
- 最新 `sample_time` 为 `2026-07-20 11:26:14`，与 236 MySQL 当前表时间基本一致。

## 6. 数据库与存储分工

### 6.1 233 MySQL：平台账号与应用数据

| 项目 | 基线 |
| --- | --- |
| 版本/端口 | MySQL 8.0 / `6603` |
| `anbo_wx` | 约 12 张表；用户、组织、权限、小程序、服务器和工单 |
| `zhiwei_assistant` | 约 9 张表；智维助手业务数据 |
| 凭据来源 | 应用 `.env` 或 root 专用配置，不进入 Git |

主要风险：`anbo@%` 历史权限偏大，应创建仅授权 `anbo_wx.*` 的应用账号并轮换。

### 6.2 236 MySQL：采集主数据

| 数据库 | 2026-07-19 文档基线 | 用途 |
| --- | ---: | --- |
| `newAlert` | 29 表，约 289 GB | 旧版采集主库 |
| `snmp_monitoring` | 26 表，约 6.6 GB | SNMP 监控数据 |
| `jiangning_API` | 11 表，约 2.6 GB | 外部接口数据 |
| `go_collector` | 24 表；2026-07-20 实测约 810 MB | 新版 Go 采集器主库 |
| `newAInew` | 17 表，约 104 MB | 旧 AI/告警业务 |
| `AiInstallation` | 5 表，约 0.4 MB | AI 安装配置 |
| `go_admin` | 11 表，约 0.4 MB | Go 管理端数据 |
| `repair_records` | 5 表，约 0.3 MB | 维修记录 |

2026-07-20 只读核验：

- MySQL 版本 `8.0.46`。
- 当前只读应用账号可见 `go_collector` 24 张表，约 810 MB。
- `olt_devices` 为 520 台。
- `olt_onu_last` 最新 `query_time` 为 `2026-07-20 11:26:15`。

主要风险：`admin_yves@%` 带全局管理员和 `GRANT OPTION`，不得作为日常应用账号。

### 6.3 20 AIOps MySQL / Elasticsearch

2026-07-19 验收基线：

| 对象 | 数量或状态 |
| --- | ---: |
| 定时分析任务 | 2，其中 1 个启用的 12 小时全局任务 |
| AI 分析运行 | 147 |
| Findings | 2,192 |
| 模型 | 17 |
| 用途绑定 | 9 |
| 故障报告 | 10 |
| 值班报修 | 10,264 |
| 运维文档 | 53 |
| 聚合主题 | 164 |

Elasticsearch 保存 Syslog、Trap、Events 和知识检索索引。单节点 `yellow` 不等于不可用，但意味着副本无法分配；后续应增加节点或按单节点策略调整副本数。

### 6.4 212 ClickHouse

主要表：

- `onu_optical_sample`：ONU 光功率历史采样；
- `onu_quality_daily_detail`：每日质差明细；
- `onu_traffic_daily`：ONU 日流量；
- `olt_if_counter_sample`：OLT 端口计数器；
- `olt_perf_sample`：OLT/板卡性能历史；
- `cmts_cm_sample`：CMTS/CM 历史采样；
- `analysis_event_candidate`：分析候选事件。

ClickHouse 用于历史、趋势和大规模分析，不应重新把全量原始历史长期堆回 236 MySQL。

## 7. 核心数据逻辑与必须保持的口径

### 7.1 当前状态、历史和汇总分层

| 层次 | 推荐存储 | 用途 |
| --- | --- | --- |
| 当前状态 | 236 MySQL | 单设备查询、最新状态、业务关联和权限过滤 |
| 原始历史 | 212 ClickHouse | 光功率、计数器、性能、CM 指标和趋势 |
| 日汇总/分析候选 | ClickHouse 为主 | 报表、质差、趋势和 AI 候选 |
| 平台账号/组织 | 233 MySQL | 登录、用户、组织、菜单、角色和审计 |
| AIOps 事务与日志 | 20 MySQL + Elasticsearch | 任务、Findings、规则、知识库、Syslog/Trap/Events |

### 7.2 外部同步设备与本地采集率

这是驾驶舱和区域统计最重要的数据口径：

- 设备总数 = 本地设备 + 外部同步设备。
- `external_database` 为空才属于本平台本地采集范围。
- 外部同步设备计入资产覆盖，但没有可靠本地采集记录时不参与本地采集率。
- 全部为外部同步的区域应显示“外部同步”，不能显示为 0% 或采集失败。
- 若业务需要外部设备健康率，必须接入外部采集结果、时间戳和状态码，不能由“无本地记录”推断。

生产例子：城北曾为 39 台设备，其中本地 1 台、外部同步 38 台。本地采集率 0% 只表示那 1 台本地设备失败，不代表另外 38 台失败。

### 7.3 ONU 质差查询

已完成的性能优化：

- 首屏列表和核心统计先返回，趋势和 Top 排行后台加载；
- `summary_only=1` 避免汇总请求重复分页明细；
- OLT Top 最多 100，端口 Top 最多 200；
- 汇总缓存跨页复用；
- 233 每约 4 分钟预热默认列表和 30 天汇总；
- 768–1680 CSS 像素使用紧凑桌面布局。

生产实测从约 27.8 秒完整等待改善为列表约 5 秒先展示；缓存命中约 0.17 秒。后续仍应通过 SQL/索引、ClickHouse 负载和接口耗时监控降低冷查询波动。

### 7.4 OLT 性能口径

- `CPU 异常`、`内存异常`、`采集失败`是三个独立条件。
- 三项都不选表示查看正常设备。
- 趋势最大值和明细最新值可能不同，页面必须标明统计时间范围。
- 无端口历史时明确显示“暂无端口历史/请选择端口”。
- 7 天、30 天趋势应随时间范围调整粒度，并支持点击异常时间点下钻设备。

## 8. 代码结构与技术栈

| 路径 | 技术 | 职责 |
| --- | --- | --- |
| `cmd/collector/` | Go 1.22 | 主采集器入口 |
| `cmd/collector-agent/` | Go 1.22 | 采集代理和健康/统计 API |
| `internal/collector/` | Go / gosnmp | 厂商适配和 SNMP 采集 |
| `internal/scheduler/` | Go | OLT、CMTS、外部 ONU 调度 |
| `internal/sink/` | Go | MySQL、ClickHouse、JSONL 写入 |
| `internal/quality/` | Go | ONU 质差规则 |
| `internal/performance/` | Go | OLT 性能采集 |
| `internal/summary/` | Go | 汇总、清理和日任务 |
| `backend/ops-platform-api/` | Flask/Python | 网管路由、权限、AIOps BFF、验收脚本 |
| `web/ops-platform/` | Vue 3、TypeScript、Vite、ECharts | 新版统一 Web |
| `sql/` | MySQL/ClickHouse SQL | 表结构、索引、迁移和菜单 |
| `deploy/233/` | systemd/Nginx/Bash | 233 正式部署和回滚 |
| `tools/` | Python | 导入、查询和一次性数据工具 |
| `docs/` | Markdown | 架构、迁移、验收和历史决策 |

前端主要依赖：Vue 3.5、Vue Router、Vite 7、TypeScript 5.8、ECharts 6、Lucide Vue。Go 侧主要依赖 gosnmp、MySQL 驱动和 Oracle 驱动。

## 9. 发布、验证与回滚边界

### 9.1 开发检查

```bash
go test ./...
go build -o bin/collector ./cmd/collector
go build -o bin/collector-agent ./cmd/collector-agent

cd web/ops-platform
npm ci
npm run build

python -m py_compile backend/ops-platform-api/ops_platform_api.py
```

### 9.2 233 发布原则

1. 前端必须从干净 Git worktree 构建，不能从混有未提交 AIOps/临时改动的目录直接上传 `dist`。
2. 后端源文件同步到 233 的 `app/routes/netops2026.py` 后，重启或 reload `zhiwei-api`。
3. 验证 7001 监听、`/wx/api/health`、登录、导航、AIOps 权限和页面构建版本。
4. 不得覆盖 `/2025/`、`/api/`，不得停止旧版 Gunicorn 或 Celery。
5. Nginx 变更先执行语法检查，切换失败必须恢复备份。

### 9.3 236 发布原则

1. 新版 Go 采集发布不得停止旧版 `newalert/newalertApi`。
2. 使用实例锁避免同一配置重复运行。
3. MySQL 是当前状态主链路；ClickHouse 辅写失败不能静默，但不能阻断 MySQL 主写。
4. 迁移或清理历史表前先确认保留策略和恢复路径。
5. 后续应将 Collector 和 Collector Agent 标准化为 systemd，并补齐健康、重启和日志轮转。

## 10. 备份与恢复

| 对象 | 计划 | 集中/异机位置 | 保留 |
| --- | --- | --- | --- |
| 233 MySQL | 每天北京时间 02:15 | 212 `/srv/backup-vault/mysql-233/daily/` | 233 本地 14 天，212 30 天 |
| 236 MySQL | 每天北京时间 02:00 | 212 `/srv/backup-vault/mysql-236/daily/` | 236 本地 14 天，212 30 天 |
| 212 ClickHouse | 每天北京时间 04:30 | 212 原生备份，同步至 236 `/var/backups/clickhouse-212/daily/` | 212 14 天，236 30 天 |

通用要求：SSH 密钥、rsync 断点续传、SHA-256、`.part` 临时文件、校验后原子改名。恢复时先进入 `restore_verify_*` 临时库、临时表或独立实例验证，禁止直接覆盖生产库。

## 11. GitHub、分支与当前工作区

| 项目 | 当前状态 |
| --- | --- |
| GitHub | `git@github.com:NJCATV/go_collector.git`，私有仓库 |
| 默认分支 | `main` |
| 2026-07-20 GitHub HEAD | `6df6119 perf: 加速质差查询并适配笔记本分辨率` |
| 开放 PR / Issue | 0 / 0 |
| 236 仓库 HEAD | `e6c7c51 Fix cockpit OLT region join` |
| 远程差异 | 236 少 13 个提交；差异集中在 233 API、Vue、AIOps、部署和文档 |

整理本文件时，本地工作区已有一项不属于本次文档整理的用户改动，必须保留并单独处理：

- `backend/ops-platform-api/ops_platform_api.py`：OLT 选项接口增加设备 `items`，同时调整 ONU 质差导出文件名。

不要把历史会话号 Markdown、客户 Excel、MAC/TSV 样本、`deliverables/`、二进制、生产运行 JSON、日志、`node_modules` 或 `dist` 提交到 GitHub。仓库的 `.gitignore` 已按此边界补充。

## 12. 已完成的重要里程碑

1. Go Collector 支持多厂商 OLT/ONU、CMTS、外部数据同步和 MySQL/ClickHouse 双写。
2. 新版 Vue 网管覆盖驾驶舱、FTTH、HFC、采集监控和系统管理。
3. 新版根入口上线，旧版迁至 `/2025/`，API 和 Celery 保持隔离。
4. 233 API 从临时 `python run.py` 切换为 systemd + Gunicorn。
5. AIOps 通过统一登录、菜单、权限和 BFF 接入，原本地弱登录停用。
6. OA 用户主数据迁移完成，并处理 OA/OSS 登录名冲突和设备区域映射。
7. 驾驶舱修正外部同步设备与本地采集率口径。
8. ONU 质差查询完成首屏拆分、缓存预热、返回量收敛和笔记本分辨率适配。
9. 233/236 MySQL 与 212 ClickHouse 已形成异机备份方案和恢复原则。

## 13. 后续优先级

### P0：运行与安全

1. 为 236 收集真实访问源，设计白名单后分阶段收敛 3339、5333、10086、18086、5000 等端口。
2. 重建 `repair_records` 运行环境和 systemd 单元，在维护窗口验证可重启。
3. 将 Go Collector 和 Collector Agent 标准化为 systemd，补齐日志轮转、自动重启和状态探针。
4. 创建 233/236 最小权限应用账号，替换 `anbo@%` 和带 `GRANT OPTION` 的日常使用方式。
5. 执行一次可审计的 233 MySQL、236 MySQL、212 ClickHouse 恢复演练。

### P1：产品与数据正确性

1. 对区域用户、组织管理员、超级管理员执行用户/组织/设备/OLT/CMTS/ONU 的服务端权限回归。
2. 若要展示外部同步设备健康率，先定义真实外部健康数据源和新鲜度。
3. 完成 OLT 性能趋势粒度切换和异常时间点下钻。
4. 继续降低 ONU 质差冷查询耗时，并增加 SQL、ClickHouse 和缓存命中监控。
5. 核验管理员完整菜单、人工角色调整和异常账号数据的最终状态。

### P2：工程治理

1. 同步 236 的 Git 仓库镜像，同时保持生产二进制变更受控。
2. 为 Flask 单文件路由逐步拆分应用工厂、服务层和数据访问层。
3. 增加 Go、API 和前端的自动化构建/测试流水线。
4. 统一交付材料标题和版本，避免 Word、PDF、页脚名称不一致。
5. 定期更新本文件的“最后核验”日期和现场事实，历史决策继续保存在 `docs/`。

## 14. 后续会话的建议起始方式

开始新任务时，先执行：

1. 阅读本文件和与任务直接相关的 `docs/` 专题文档。
2. 查看 `git status -sb`，区分用户已有改动和本次任务范围。
3. 若涉及生产状态，只读核验目标服务、端口和数据最新时间，不直接照搬历史文档。
4. 若涉及发布，确认目标服务器、备份、干净构建、旧版隔离和回滚点。
5. 若涉及数据库，先确认数据口径、权限和查询成本；默认只读，恢复先到临时库。

可直接引用的简短上下文：

> 当前项目是南京安播智维平台主仓库：233 承载统一 Web/API/权限与 AIOps BFF，236 承载新旧采集和 MySQL，20 保留 AIOps MySQL/ELK/Scheduler，212 承载 ClickHouse 与集中备份。新版根入口已上线，旧版保留在 `/2025/`。外部同步设备只计入资产覆盖，不参与本地采集率。当前重点是 236 运行标准化与端口收敛、最小权限账号、权限回归、外部健康源、性能趋势下钻和备份恢复演练。

## 15. 相关正式文档

| 文档 | 主题 |
| --- | --- |
| `README.md` | 仓库总说明、部署和备份 |
| `docs/production-runtime-audit-20260719.md` | 233/236/20/212 生产运行核查 |
| `docs/aiops-final-architecture-20260719.md` | AIOps 最终接入架构 |
| `docs/oa-user-master-migration-20260719.md` | OA 用户、组织和区域迁移 |
| `docs/quality-query-performance-and-responsive-20260719.md` | ONU 质差性能与响应式优化 |
| `docs/backend-api-data-contract-20260701.md` | API 与存储契约 |
| `docs/snmp-collector-next-roadmap-20260626.md` | 采集与数据分层路线图 |
| `docs/data-retention-plan-20260527.md` | 数据保留与清理 |
| `docs/engineering-standard.md` | 工程规则和安全边界 |
