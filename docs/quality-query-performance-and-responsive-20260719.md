# ONU 质差查询性能与分辨率适配记录

## 一、问题结论

| 问题 | 根因 |
|---|---|
| 质差页面首次打开慢 | 一次请求串行执行统计、分页、趋势、OLT Top、端口 Top 等 ClickHouse 聚合，并继续访问 236 MySQL 补全设备、BOSS 与业务数据 |
| 页面操作卡顿 | 完整响应约 1.51 MB，包含 2,842 个端口聚合和 365 个 OLT 聚合，前端一次创建数千个排行节点 |
| 翻页重复等待 | 汇总缓存键包含页码和每页条数，换页后相同汇总无法复用 |
| 普通笔记本需缩放 | 侧栏、内容边距、卡片、表格行高均按大屏固定像素设计；低 CSS 视口宽度下有效内容区不足 |

## 二、优化方案

| 层次 | 调整 |
|---|---|
| 首屏 | 列表与核心统计先请求，约 5 秒可用；趋势和 Top 排行后台继续加载 |
| 查询 | 新增 `summary_only=1`，汇总请求不再重复查询和补全分页明细 |
| 返回量 | OLT Top 限制 100 台，端口 Top 限制 200 个，并只返回页面使用字段 |
| 缓存 | 汇总缓存键不再包含页码和每页条数，可跨页复用 |
| 预热 | `zhiwei-quality-cache.timer` 每 4 分钟刷新默认列表和 30 天汇总缓存 |
| 自适应 | 768–1680 CSS 像素采用紧凑桌面密度；缩小侧栏、边距、卡片和表格行高 |
| 窄屏 | 质差主内容不足 880 像素时，两个排行卡自动改为单列；不足 980 像素时筛选区与结果区改为上下布局 |

## 三、生产实测

| 场景 | 优化前 | 优化后 |
|---|---:|---:|
| 默认完整响应 | 约 27.8 秒 | 列表约 5 秒先展示，汇总后台加载 |
| 完整响应体 | 约 1.51 MB | 汇总约 40 KB，列表约 12 KB |
| 默认列表缓存命中 | 未单独预热 | 约 0.17 秒 |
| 默认汇总缓存命中 | 约 0.09 秒但按页分裂 | 约 0.03 秒且跨页复用 |
| 返回端口排行 | 2,842 行 | 最多 200 行 |
| 返回 OLT 排行 | 365 行 | 最多 100 行 |

冷查询耗时受 ClickHouse 当时负载影响，会有波动；优化重点是优先交付可操作列表、减少重复计算和传输，并通过定时预热避免普通用户承担冷启动。

## 四、生产服务

| 项目 | 内容 |
|---|---|
| 预热脚本 | `/home/yvesyuan/deploy/quality-cache-warmer.py` |
| systemd 服务 | `zhiwei-quality-cache.service`，一次性任务 |
| systemd 定时器 | `zhiwei-quality-cache.timer`，每 4 分钟执行 |
| API 备份 | `/var/backups/zhiwei-quality-performance/<UTC时间戳>/` |
| 最终发布备份 | `/var/backups/zhiwei-quality-performance/20260719T091809Z/` |

常用检查命令：

```bash
systemctl status zhiwei-quality-cache.timer
systemctl list-timers zhiwei-quality-cache.timer
journalctl -u zhiwei-quality-cache.service -n 30 --no-pager
```

## 五、验收结果

| 验收项 | 结果 |
|---|---|
| 前端 TypeScript 检查与 Vite 构建 | 通过 |
| Python 语法检查 | 通过 |
| 未登录 API 仍返回 401 | 通过 |
| `zhiwei-api`、`newalertgunicorn`、`alertcelery` | active |
| 缓存预热任务 | Result=success，退出码 0 |
| 缓存预热定时器 | active，已安排下一次运行 |
