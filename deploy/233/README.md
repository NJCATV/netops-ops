# 233 统一网管部署

`deploy/233/` 存放 `172.31.1.233` 上统一网管入口的可复现部署资料；该节点负责 Nginx、Vue 静态站点与平台 BFF 的生产入口。

| 文件或目录 | 用途 |
| --- | --- |
| `install-zhiwei-production.sh` | zhiwei API 生产服务安装/更新 |
| `zhiwei-api.service` | systemd 服务单元模板 |
| `nginx-root-entry-locations.conf` | 新版根入口和旧版兼容 location 配置 |
| `nginx-2026-location.conf` | 2026 入口相关 Nginx 片段 |
| `install-zhiwei-root-entry.sh` | 根入口部署辅助脚本 |
| `install-quality-performance.sh`、`warm_quality_cache.py`、timer/service | ONU 质差性能缓存预热 |
| `oa-user-migration/` | OA 用户主数据迁移与验收；详见其 README |

部署前先阅读根目录 [README.md](../../README.md) 与 [架构地图](../../docs/platform-architecture-and-module-map.md)，并在变更后同步更新本目录的模板和文档。真实 Nginx 主配置、环境变量、证书和密码不提交。
