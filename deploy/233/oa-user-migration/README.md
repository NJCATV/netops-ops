# OA 用户主数据迁移

| 项目 | 说明 |
|---|---|
| 主数据来源 | `anbo_wx.users_from_oa` |
| 有效用户 | 排除 OA 用户名中包含 `admin` 的测试账号 |
| 唯一匹配 | 以规范化手机号匹配原 `users`，保留该用户已有 OSS 绑定 |
| 登录方式 | 手机号、OA 用户名、OSS 账号三者任一 |
| 初始密码 | `Jscn@` + 手机号后四位 |
| 初始权限 | OA 用户全部为 `internal / normal_user / active` |
| 保底管理 | `admin` 转为 `system / super_admin`，不属于 OA 人员主数据 |
| 首次改密 | Web/微信端每次登录提醒，均允许暂时跳过 |
| OSS 绑定 | 不再作为登录后的全局前置条件，也不在普通菜单弹窗；仅在智能装维等 OSS 能力入口按需绑定 |

## 执行顺序

| 顺序 | 命令/动作 | 目的 |
|---:|---|---|
| 1 | `backup_anbo_wx.py` | 生成全库压缩备份与 SHA-256 |
| 2 | `apply_source_changes.py` | 幂等修改后端模型、登录和用户管理逻辑 |
| 3 | 复制 Alembic 文件并执行 `flask db upgrade` | 增加唯一列 `users.oa_username` |
| 4 | `migrate_oa_users.py` | 只读预检并输出计划 |
| 5 | `migrate_oa_users.py --apply` | 执行用户、组织和 236 设备区域映射迁移 |
| 6 | 登录/API/计数验证 | 确认 1,641 个 OA 用户、密码和权限状态 |
| 7 | `migrate_oa_users.py --drop-source-tables-only` | 最终校验并删除两个一次性源表 |

`migrate_oa_users.py` 每次都会在 `/home/yvesyuan/deploy/backups/oa-user-migration/`
保存 JSON 审计文件。区域映射规则为：分公司/城区只映射对应设备区域，总部部门和安播中心映射全部 11 个区域，`省AI门户游客` 不映射设备区域。AIOps 数据不使用该设备区域过滤。
