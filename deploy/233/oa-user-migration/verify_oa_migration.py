"""生产迁移后的非破坏性验收；改密测试结束后恢复原哈希与状态。"""

import json

from flask import g
from sqlalchemy import inspect
from run import app
from app.extensions import db
from app.models import User
from app.routes.netops2026 import query_all
from app.utils.jwt import create_access_token


def default_password(user):
    return f"Jscn@{user.mobile[-4:]}"


def login(client, account, password):
    response = client.post("/api/netops2026/auth/login", json={"account": account, "password": password})
    body = response.get_json(silent=True) or {}
    assert response.status_code == 200 and body.get("code") == 0, (account, response.status_code, body)
    return body["data"]


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


with app.app_context():
    client = app.test_client()
    plain = User.query.filter(
        User.oa_username.isnot(None), User.oss_account.is_(None), User.role_code == "normal_user"
    ).first()
    with_oss = User.query.filter(
        User.oa_username.isnot(None),
        User.oss_account.isnot(None),
        User.oss_account != "lining",
        User.role_code == "normal_user",
    ).first()
    central = User.query.filter(
        User.oa_username.isnot(None), User.org.has(name="技术工程部"), User.role_code == "normal_user"
    ).first()
    branch = User.query.filter(
        User.oa_username.isnot(None), User.org.has(name="江宁子公司"), User.role_code == "normal_user"
    ).first()
    visitor = User.query.filter(
        User.oa_username.isnot(None), User.org.has(name="省AI门户游客"), User.role_code == "normal_user"
    ).first()
    # 保底管理员允许在后台修改手机号；OSS 账号 admin 是稳定识别标识。
    admin = User.query.filter_by(oss_account="admin", role_code="super_admin").one()
    assert all((plain, with_oss, central, branch, visitor, admin))

    plain_by_phone = login(client, plain.mobile, default_password(plain))
    plain_by_oa = login(client, plain.oa_username, default_password(plain))
    assert plain_by_phone["user"]["id"] == plain.id == plain_by_oa["user"]["id"]
    assert plain_by_phone["next_action"] == "change_password"

    oss_results = [
        login(client, with_oss.mobile, default_password(with_oss)),
        login(client, with_oss.oa_username, default_password(with_oss)),
        login(client, with_oss.oss_account, default_password(with_oss)),
    ]
    assert {item["user"]["id"] for item in oss_results} == {with_oss.id}

    collision_oa = User.query.filter_by(oa_username="lining").one()
    collision_oss = User.query.filter_by(oss_account="lining").one()
    assert collision_oa.id != collision_oss.id
    assert login(client, "lining", default_password(collision_oa))["user"]["id"] == collision_oa.id
    assert login(client, "lining", default_password(collision_oss))["user"]["id"] == collision_oss.id

    token = plain_by_phone["access_token"]
    me = client.get("/api/netops2026/auth/me", headers=bearer(token))
    assert me.status_code == 200 and me.get_json()["data"]["user"]["oa_username"] == plain.oa_username
    navigation = client.get("/api/netops2026/navigation", headers=bearer(token))
    keys = {item["menu_key"] for item in navigation.get_json()["data"]["items"]}
    assert navigation.status_code == 200 and "netops.aiops" in keys

    original_hash, original_status = plain.password_hash, plain.password_status
    changed = client.post(
        "/api/netops2026/auth/change-password",
        headers=bearer(token),
        json={"old_password": default_password(plain), "new_password": "Test2026"},
    )
    assert changed.status_code == 200 and changed.get_json()["data"]["next_action"] == "home"
    assert login(client, plain.oa_username, "Test2026")["user"]["id"] == plain.id
    plain.password_hash, plain.password_status = original_hash, original_status
    db.session.commit()

    def regions_for(user):
        # 本脚本为提高速度复用一个 app_context；清掉仅限单请求使用的 g 缓存。
        for key in ("_netops_allowed_device_regions", "_netops_authorized_device_ids"):
            if hasattr(g, key):
                delattr(g, key)
        token = create_access_token(user.id)
        response = client.get("/api/netops2026/device-orgs", headers=bearer(token))
        assert response.status_code == 200
        return {item["region_code"] for item in response.get_json()["data"]["items"] if item["node_type"] == "region"}

    branch_regions = regions_for(branch)
    central_regions = regions_for(central)
    visitor_regions = regions_for(visitor)
    admin_token = create_access_token(admin.id)
    admin_navigation = client.get("/api/netops2026/navigation", headers=bearer(admin_token))
    admin_keys = {item["menu_key"] for item in admin_navigation.get_json()["data"]["items"]}
    admin_users = client.get("/api/netops2026/access/users?page=1&page_size=20", headers=bearer(admin_token))
    admin_orgs = client.get("/api/netops2026/access/orgs/tree", headers=bearer(admin_token))
    assert admin_users.status_code == admin_orgs.status_code == 200
    user_data = admin_users.get_json()["data"]
    org_data = admin_orgs.get_json()["data"]

    result = {
        "users_total": User.query.count(),
        "oa_users": User.query.filter(User.oa_username.isnot(None)).count(),
        "normal_oa_users": User.query.filter(User.oa_username.isnot(None), User.role_code == "normal_user").count(),
        "privileged_oa_users": User.query.filter(
            User.oa_username.isnot(None), User.role_code.in_(("org_admin", "super_admin"))
        ).count(),
        "oa_users_with_oss": User.query.filter(User.oa_username.isnot(None), User.oss_account.isnot(None)).count(),
        "phone_login": True,
        "oa_login": True,
        "oss_login": True,
        "cross_namespace_collision_login": True,
        "first_password_change_and_restore": True,
        "initial_password_can_access_navigation": True,
        "normal_user_aiops_visible": "netops.aiops" in keys,
        "branch_regions": sorted(branch_regions),
        "central_region_count": len(central_regions),
        "visitor_region_count": len(visitor_regions),
        "admin_system_menus_visible": all(key in admin_keys for key in ("netops.users", "netops.orgs", "netops.permissions")),
        "admin_user_list_total": user_data["total"],
        "admin_org_tree_total": org_data["total"],
        "admin_user_list_has_oa_username": any(item.get("oa_username") for item in user_data["items"]),
        "collector_mapping": query_all("SELECT COUNT(*) rows_count,COUNT(DISTINCT user_org_id) org_count FROM netops2026_user_device_region_map")[0],
        "anbo_wx_table_count": len(inspect(db.engine).get_table_names()),
    }
    assert result["users_total"] == 1642
    assert result["admin_user_list_total"] == result["admin_org_tree_total"] == 1642
    assert result["admin_user_list_has_oa_username"]
    # 迁移落库时 1641 个 OA 用户均为普通用户；之后管理员可按业务需要人工提权。
    assert result["oa_users"] == 1641
    assert result["normal_oa_users"] + result["privileged_oa_users"] == result["oa_users"]
    assert branch_regions == {"jiangning"}
    assert len(central_regions) == 11
    assert visitor_regions == set()
    assert result["admin_system_menus_visible"]
    print(json.dumps(result, ensure_ascii=False, indent=2))
