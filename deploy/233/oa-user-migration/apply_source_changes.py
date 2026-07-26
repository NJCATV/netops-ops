"""幂等更新 233 上 anbo_wx 后端用户模型、登录与管理逻辑。"""

from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone


PROJECT_ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/srv/netops/netops-littleProgram")
STAMP = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
BACKUP_ROOT = PROJECT_ROOT / "backend" / "deploy-backups" / f"oa-user-master-{STAMP}"


def update(relative_path, changes):
    path = PROJECT_ROOT / relative_path
    content = path.read_text(encoding="utf-8")
    original = content
    for old, new, label in changes:
        if new and new in content:
            continue
        if not new and old not in content:
            # 删除型变更已执行时，新片段为空，按幂等成功处理。
            continue
        if old not in content:
            raise RuntimeError(f"{relative_path}: 找不到待替换片段 {label}")
        content = content.replace(old, new, 1)
    if content == original:
        print(f"已是最新: {relative_path}")
        return
    backup = BACKUP_ROOT / relative_path
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup)
    path.write_text(content, encoding="utf-8")
    print(f"已更新: {relative_path}")


update("backend/app/models.py", [
    (
        '    mobile = db.Column(db.String(32), nullable=False, unique=True)\n    oss_account = db.Column(db.String(64), nullable=True, unique=True)',
        '    mobile = db.Column(db.String(32), nullable=False, unique=True)\n    oa_username = db.Column(db.String(64), nullable=True, unique=True)\n    oss_account = db.Column(db.String(64), nullable=True, unique=True)',
        "User.oa_username",
    ),
    (
        '            "mobile": self.mobile,\n            "oss_account": self.oss_account,',
        '            "mobile": self.mobile,\n            "oa_username": self.oa_username,\n            "oss_account": self.oss_account,',
        "公开 OA 用户名",
    ),
])

update("backend/app/services/auth_service.py", [
    (
        'def password_is_strong(password):\n    if len(password or "") < 12:\n        return False\n    classes = sum(bool(re.search(pattern, password)) for pattern in (r"[a-z]", r"[A-Z]", r"\\d", r"[^A-Za-z0-9]"))\n    return classes >= 3',
        'def password_is_strong(password):\n    """平台密码至少 8 位，并包含大小写字母、数字、特殊字符中的至少两类。"""\n    if len(password or "") < 8:\n        return False\n    classes = sum(bool(re.search(pattern, password)) for pattern in (r"[a-z]", r"[A-Z]", r"\\d", r"[^A-Za-z0-9]"))\n    return classes >= 2',
        "放宽平台密码强度为 8 位两类字符",
    ),
    (
        'return None, "新密码至少 12 位，并需包含大小写字母、数字、特殊字符中的至少三类"',
        'return None, "新密码至少 8 位，并需包含大小写字母、数字、特殊字符中的至少两类"',
        "更新密码强度提示",
    ),
    (
        'def find_user_by_account(account):\n    return User.query.filter(or_(User.mobile == account, User.oss_account == account)).first()',
        'def find_users_by_account(account):\n    normalized = (account or "").strip()\n    return User.query.filter(or_(\n        User.mobile == normalized,\n        User.oa_username == normalized,\n        User.oss_account == normalized,\n    )).all()',
        "三账号登录",
    ),
    (
        '    user = find_user_by_account(account)\n    if user is None:\n        add_login_log(request, account, "fail", fail_reason="user not found")\n        db.session.commit()\n        return None, "account or password is incorrect"\n\n    if user.status != "active":\n        add_login_log(request, account, "fail", user=user, fail_reason="user disabled")\n        db.session.commit()\n        return None, "account or password is incorrect"\n\n    if not verify_password(user.password_hash, password):\n        add_login_log(request, account, "fail", user=user, fail_reason="invalid password")\n        db.session.commit()\n        return None, "account or password is incorrect"',
        '    candidates = find_users_by_account(account)\n    if not candidates:\n        add_login_log(request, account, "fail", fail_reason="user not found")\n        db.session.commit()\n        return None, "account or password is incorrect"\n\n    matches = [\n        candidate for candidate in candidates\n        if candidate.status == "active" and verify_password(candidate.password_hash, password)\n    ]\n    if len(matches) != 1:\n        reason = "ambiguous account" if len(matches) > 1 else "invalid password or disabled user"\n        add_login_log(request, account, "fail", fail_reason=reason)\n        db.session.commit()\n        return None, "account or password is incorrect"\n    user = matches[0]',
        "按密码唯一解析跨命名空间同名账号",
    ),
])

update("backend/app/services/user_service.py", [
    (
        'def initial_password():\n    # 临时密码不可由手机号推导；首次登录仍会强制修改。\n    return secrets.token_urlsafe(12)',
        'def initial_password(mobile):\n    """OA 人员使用公司初始密码规则；非手机号系统账号仍使用随机密码。"""\n    normalized = re.sub(r"\\D", "", mobile or "")\n    if VALID_MOBILE_RE.fullmatch(normalized):\n        return f"Jscn@{normalized[-4:]}"\n    return secrets.token_urlsafe(12)',
        "统一初始密码",
    ),
    (
        '    oss_account = (payload.get("oss_account") or "").strip() or None\n',
        '    oss_account = (payload.get("oss_account") or "").strip() or None\n    oa_username = (payload.get("oa_username") or "").strip() or None\n',
        "读取 OA 用户名",
    ),
    (
        '        "oss_account": oss_account,\n',
        '        "oss_account": oss_account,\n        "oa_username": oa_username,\n',
        "保存 OA 用户名",
    ),
    (
        '        query = query.filter(or_(User.real_name.like(like), User.mobile.like(like), User.oss_account.like(like)))',
        '        query = query.filter(or_(\n            User.real_name.like(like),\n            User.mobile.like(like),\n            User.oa_username.like(like),\n            User.oss_account.like(like),\n        ))',
        "按 OA 搜索",
    ),
    (
        '    if data["oss_account"] and User.query.filter_by(oss_account=data["oss_account"]).first():\n        return None, "oss_account already exists"\n\n    temporary_password = initial_password()',
        '    if data["oss_account"] and User.query.filter_by(oss_account=data["oss_account"]).first():\n        return None, "oss_account already exists"\n    if data["oa_username"] and User.query.filter_by(oa_username=data["oa_username"]).first():\n        return None, "oa_username already exists"\n\n    temporary_password = initial_password(data["mobile"])',
        "新增用户 OA 唯一性",
    ),
    (
        '    if data["oss_account"]:\n        oss_owner = User.query.filter(User.oss_account == data["oss_account"], User.id != target.id).first()\n        if oss_owner:\n            return None, "oss_account already exists"\n\n    old_oss = target.oss_account',
        '    if data["oss_account"]:\n        oss_owner = User.query.filter(User.oss_account == data["oss_account"], User.id != target.id).first()\n        if oss_owner:\n            return None, "oss_account already exists"\n    if data["oa_username"]:\n        oa_owner = User.query.filter(User.oa_username == data["oa_username"], User.id != target.id).first()\n        if oa_owner:\n            return None, "oa_username already exists"\n\n    old_oss = target.oss_account',
        "编辑用户 OA 唯一性",
    ),
    ('    temporary_password = initial_password()\n    target.password_hash', '    temporary_password = initial_password(target.mobile)\n    target.password_hash', "重置初始密码"),
])

update("backend/app/routes/netops2026.py", [
    (
        'from app.services.auth_service import login as base_login\nfrom app.extensions import db',
        'from app.services.auth_service import change_password as base_change_password, login as base_login\nfrom app.services.permission_service import next_action_for_user\nfrom app.extensions import db',
        "接入改密服务",
    ),
    (
        '        "username": public.get("oss_account") or public.get("mobile") or public.get("account") or str(g.current_user.id),',
        '        "username": public.get("oa_username") or public.get("mobile") or public.get("oss_account") or public.get("account") or str(g.current_user.id),',
        "AIOps 使用 OA 主身份",
    ),
    (
        'def me_route():\n    return success({"user": g.current_user.to_public_dict()})\n\n\n@netops2026_bp.route("/aiops/<path:path>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])',
        'def me_route():\n    return success({"user": g.current_user.to_public_dict(), "next_action": next_action_for_user(g.current_user)})\n\n\n@netops2026_bp.post("/auth/change-password")\n@login_required\ndef change_password_route():\n    payload = request.get_json(silent=True) or {}\n    data, error = base_change_password(\n        request,\n        g.current_user,\n        payload.get("old_password") or "",\n        payload.get("new_password") or "",\n    )\n    if error:\n        return fail(BAD_REQUEST, error)\n    return success(data)\n\n\n@netops2026_bp.route("/aiops/<path:path>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])',
        "平台首次改密接口",
    ),
    (
        '        query = query.filter(or_(User.real_name.like(like), User.mobile.like(like), User.oss_account.like(like)))',
        '        query = query.filter(or_(\n            User.real_name.like(like),\n            User.mobile.like(like),\n            User.oa_username.like(like),\n            User.oss_account.like(like),\n        ))',
        "用户列表支持 OA 搜索",
    ),
    (
        'def aiops_page_audience_allowed():\n    """AIOps pages are available to management roles and 安播中心 staff.\n\n    This is only the page boundary. Once admitted, operational AIOps data is\n    global and is deliberately not filtered by device region or organization.\n    """\n    role = getattr(g.current_user, "role_code", "normal_user") or "normal_user"\n    if role in ("org_admin", "super_admin"):\n        return True\n    public = g.current_user.to_public_dict()\n    return "安播中心" in str(public.get("org_name") or "")',
        'def aiops_page_audience_allowed():\n    """Use menu role/type permission only; AIOps never applies org/region scope."""\n    return True',
        "AIOps 取消组织区域门槛",
    ),
])

update("miniapp/src/pages/menu/index.vue", [
    (
        '      user.value = data.user || getStoredUser()\n      showOssReminderIfNeeded(user.value)\n      return listApps()',
        '      user.value = data.user || getStoredUser()\n      return listApps()',
        "取消普通功能入口的全局 OSS 提醒",
    ),
    (
        '''function showOssReminderIfNeeded(currentUser) {
  if (!currentUser || currentUser.oss_bind_status === 'bound' || uni.getStorageSync('oss_reminder_skipped')) {
    return
  }

  uni.showModal({
    title: 'OSS 账号未绑定',
    content: '绑定后可使用 OSS 相关能力。现在可以先进入系统，稍后在“我的”页面绑定。',
    confirmText: '去绑定',
    cancelText: '稍后',
    success(result) {
      uni.setStorageSync('oss_reminder_skipped', true)
      if (result.confirm) {
        uni.navigateTo({ url: '/pages/auth/bind-oss/index' })
      }
    }
  })
}

''',
        '',
        "删除全局 OSS 弹窗",
    ),
])

update("miniapp/src/pages/auth/change-password/index.vue", [
    (
        '      <button class="primary-button submit-button" :loading="submitting" :disabled="submitting" @tap="submit">保存</button>',
        '      <button class="primary-button submit-button" :loading="submitting" :disabled="submitting" @tap="submit">保存</button>\n      <button class="skip-button" :disabled="submitting" @tap="skip">暂时跳过</button>',
        "首次改密暂时跳过按钮",
    ),
    (
        'const submitting = ref(false)\n\nfunction submit() {',
        "const submitting = ref(false)\n\nfunction skip() {\n  uni.switchTab({ url: '/pages/menu/index' })\n}\n\nfunction submit() {",
        "首次改密跳过动作",
    ),
    (
        '.submit-button {\n  width: 100%;\n  margin-top: 34rpx;\n}',
        '.submit-button {\n  width: 100%;\n  margin-top: 34rpx;\n}\n\n.skip-button {\n  width: 100%;\n  margin-top: 18rpx;\n  border: 0;\n  background: transparent;\n  color: #64748b;\n  font-size: 28rpx;\n}',
        "首次改密跳过样式",
    ),
])

print(f"源码备份目录: {BACKUP_ROOT}")
