# AIOps page migration coverage

Authoritative source: `F:\codeXSpace\AIOps\frontend\src\App.vue` navigation and `app/api` routes.

| Legacy AIOps view | Unified route | Result | Ownership |
|---|---|---|---|
| 智能态势首页 | `/aiops` | Migrated | NetOps frontend + AIOps runtime API |
| 运维看板 / 手动分析 | `/aiops/analysis` | Migrated | Organization-scoped runs and findings |
| 实时 Events | `/aiops/events` | Migrated | Device-region scoped |
| 实时 Syslog | `/aiops/syslog` | Migrated | Device-region scoped |
| SNMP Trap | `/aiops/trap` | Migrated | Device-region scoped |
| AI 分析历史 | `/aiops/analysis` | Consolidated | Same page as manual analysis |
| AI 分析规则 | `/aiops/rules` | Migrated with parse/edit/toggle/delete | Super admin; rules are global |
| 定时分析任务 | `/aiops/tasks` | Migrated with create/edit/run/toggle/delete | Organization-scoped |
| 故障知识库 / AI 问答 | `/aiops/knowledge`, `/ai-assistant` | Migrated and split | Shared curated KB; per-user chat sessions |
| 模型供应商 | `/aiops/models` | Full CRUD + discovery | Super admin |
| 模型清单 | `/aiops/models` | Full CRUD + connectivity test | Super admin |
| 用途绑定 | `/aiops/models` | Editable ordered bindings | Super admin |
| 系统设置 | `/aiops/settings` | Migrated | AIOps-only runtime settings |
| QQ 状态 | `/aiops/settings` | Migrated | Signed service identity replaces bot login |
| AI 问答 / QQ / 操作 / 登录日志 | `/aiops/audit` | Consolidated | Super admin |
| AIOps 用户管理 | `/users` | Replaced, not copied | NetOps account and organization management |
| AIOps 角色管理 | `/permissions` | Replaced, not copied | NetOps role/menu permissions |

The legacy standalone login and legacy `users` API are intentionally unavailable through the BFF. This is a replacement by the platform identity boundary, not an omitted page.

MIB dictionaries and Trap alarm definitions do not have a legacy interactive page/API in the authoritative frontend. Their import/export scripts remain data-plane operational tooling on JSCN-20 and are therefore not represented as a fabricated UI page.
