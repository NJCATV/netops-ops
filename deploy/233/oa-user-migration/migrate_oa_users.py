"""将 users_from_oa 一次性迁移为统一 users 主数据。

默认只做预检；传入 --apply 执行。验证完成后单独传入 --drop-source-tables
清理 users_from_oa 与 sys_area_org_mapping。
"""

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import re

from sqlalchemy import text

from run import app
from app.extensions import db
from app.models import OrgUnit, User
from app.routes.netops2026 import DEVICE_REGION_LABELS, mysql_conn
from app.utils.security import hash_password


AREA_EXISTING_ORG_IDS = {
    "gaochun": 41,
    "jiangning": 66,
    "liuhe": 92,
    "pukou": 112,
    "qixia": 155,
    "yuhua": 176,
    "lishui": 190,
}
AREA_DEVICE_REGION = {
    "jianye": "chengxi",
    "qinhuai": "chengnan",
    "xuanwu": "chengbei",
    "gulou": "chengdong",
    "gaochun": "gaochun",
    "jiangning": "jiangning",
    "lishui": "lishui",
    "liuhe": "liuhe",
    "pukou": "pukou",
    "qixia": "qixia",
    "yuhua": "yuhua",
}
NO_DEVICE_ACCESS_AREAS = {"visitor"}
USER_REFERENCES = (
    ("login_logs", "user_id"),
    ("operation_logs", "user_id"),
    ("server_assets", "owner_id"),
    ("work_order_comments", "user_id"),
    ("work_order_logs", "actor_id"),
    ("work_orders", "assignee_id"),
    ("work_orders", "creator_id"),
)
MOBILE_RE = re.compile(r"1[3-9]\d{9}")


def rows(sql, params=None):
    return [dict(row) for row in db.session.execute(text(sql), params or {}).mappings().all()]


def normalized_mobile(value):
    return re.sub(r"[\s-]", "", str(value or "").strip())


def initial_password(mobile):
    return f"Jscn@{mobile[-4:]}"


def load_source():
    source = rows("""
        SELECT username,phone,area,username_zh,is_active
        FROM users_from_oa ORDER BY id,username
    """)
    mappings = rows("""
        SELECT area,org_name FROM sys_area_org_mapping
        WHERE is_active=1 ORDER BY id
    """)
    return source, mappings


def preflight(source, mappings, break_glass_account):
    errors = []
    excluded = [item for item in source if "admin" in str(item["username"] or "").lower()]
    valid = [item for item in source if item not in excluded]
    by_area = defaultdict(list)
    for item in mappings:
        by_area[str(item["area"] or "").strip()].append(str(item["org_name"] or "").strip())

    usernames = defaultdict(list)
    phones = defaultdict(list)
    for item in valid:
        item["username"] = str(item["username"] or "").strip()
        item["phone"] = normalized_mobile(item["phone"])
        item["area"] = str(item["area"] or "").strip()
        item["username_zh"] = str(item["username_zh"] or "").strip()
        usernames[item["username"].lower()].append(item)
        phones[item["phone"]].append(item)
        if not item["username"] or len(item["username"]) > 64:
            errors.append(f"OA 用户名无效: {item['username']!r}")
        if not MOBILE_RE.fullmatch(item["phone"]):
            errors.append(f"手机号无效: {item['username']} / {item['phone']}")
        if not item["username_zh"] or len(item["username_zh"]) > 64:
            errors.append(f"姓名无效: {item['username']} / {item['username_zh']!r}")
        if len(by_area[item["area"]]) != 1:
            errors.append(f"区域映射不是唯一值: {item['area']} -> {by_area[item['area']]}")
    errors.extend(f"OA 用户名重复: {key}" for key, value in usernames.items() if len(value) != 1)
    errors.extend(f"OA 手机号重复: {key}" for key, value in phones.items() if len(value) != 1)

    current = User.query.all()
    users_by_phone = {normalized_mobile(user.mobile): user for user in current}
    break_glass = next((user for user in current if break_glass_account in {user.mobile, user.oss_account}), None)
    if break_glass is None:
        errors.append(f"保底管理员不存在: {break_glass_account}")

    identity_targets = defaultdict(set)
    for item in valid:
        target = item["phone"]
        identity_targets[item["phone"].lower()].add(target)
        identity_targets[item["username"].lower()].add(target)
        matched = users_by_phone.get(item["phone"])
        if matched and matched.oss_account:
            identity_targets[matched.oss_account.lower()].add(target)
    if break_glass:
        target = f"system:{break_glass.id}"
        for value in (break_glass.mobile, break_glass.oss_account):
            if value:
                identity_targets[value.lower()].add(target)
    collisions = {key: sorted(value) for key, value in identity_targets.items() if len(value) > 1}
    area_org_name = {area: names[0] for area, names in by_area.items() if len(names) == 1}
    return {
        "valid": valid,
        "excluded": excluded,
        "current": current,
        "users_by_phone": users_by_phone,
        "break_glass": break_glass,
        "area_org_name": area_org_name,
        "identity_collisions": collisions,
        "errors": errors,
    }


def resolve_orgs(plan, apply_changes):
    root = OrgUnit.query.filter_by(level=1).order_by(OrgUnit.id).first()
    if root is None:
        raise RuntimeError("找不到一级根组织")
    result = {}
    created = []
    renamed = []
    next_sort = max([item.sort_order or 0 for item in OrgUnit.query.filter_by(level=2).all()] + [0]) + 10
    for area, org_name in sorted(plan["area_org_name"].items()):
        org = OrgUnit.query.filter_by(name=org_name, level=2).order_by(OrgUnit.id).first()
        if org is None and area in AREA_EXISTING_ORG_IDS:
            org = db.session.get(OrgUnit, AREA_EXISTING_ORG_IDS[area])
            if org is None or org.level != 2:
                raise RuntimeError(f"区域 {area} 的旧二级组织不存在")
            renamed.append({"id": org.id, "old_name": org.name, "new_name": org_name})
            if apply_changes:
                org.name = org_name
        if org is None:
            if apply_changes:
                org = OrgUnit(
                    name=org_name,
                    level=2,
                    parent_id=root.id,
                    path="",
                    sort_order=next_sort,
                    status="active",
                )
                db.session.add(org)
                db.session.flush()
                org.path = f"{root.path or '/'}{org.id}/"
            else:
                org = type("PlannedOrg", (), {"id": None, "name": org_name})()
            created.append({"area": area, "name": org_name, "id": org.id})
            next_sort += 10
        result[area] = org
    return root, result, created, renamed


def delete_user_relations(user_id):
    db.session.execute(text("DELETE FROM server_asset_shares WHERE user_id=:user_id"), {"user_id": user_id})
    for table_name, column_name in USER_REFERENCES:
        db.session.execute(
            text(f"UPDATE {table_name} SET {column_name}=NULL WHERE {column_name}=:user_id"),
            {"user_id": user_id},
        )


def sync_collector_mappings(orgs):
    all_regions = sorted(DEVICE_REGION_LABELS)
    with mysql_conn() as conn:
        with conn.cursor() as cursor:
            for area, org in orgs.items():
                cursor.execute("DELETE FROM netops2026_user_device_region_map WHERE user_org_id=%s", (org.id,))
                if area in NO_DEVICE_ACCESS_AREAS:
                    continue
                regions = [AREA_DEVICE_REGION[area]] if area in AREA_DEVICE_REGION else all_regions
                cursor.executemany(
                    "INSERT INTO netops2026_user_device_region_map(user_org_id,user_org_name,device_region,enabled) VALUES(%s,%s,%s,1)",
                    [(org.id, org.name, region) for region in regions],
                )
        conn.commit()


def migrate(plan, orgs, root):
    break_glass = plan["break_glass"]
    break_glass.user_type = "system"
    break_glass.role_code = "super_admin"
    break_glass.status = "active"
    break_glass.org_id = root.id
    break_glass.manage_org_id = None
    break_glass.oa_username = None

    matched = 0
    inserted = 0
    retained_oss = 0
    keep_ids = {break_glass.id}
    for item in plan["valid"]:
        user = plan["users_by_phone"].get(item["phone"])
        if user:
            matched += 1
        else:
            user = User(mobile=item["phone"], real_name=item["username_zh"], password_hash="pending")
            db.session.add(user)
            db.session.flush()
            inserted += 1
        keep_ids.add(user.id)
        if user.oss_account:
            retained_oss += 1
        user.oa_username = item["username"]
        user.user_type = "internal"
        user.mobile = item["phone"]
        user.real_name = item["username_zh"]
        user.org_id = orgs[item["area"]].id
        user.role_code = "normal_user"
        user.manage_org_id = None
        user.status = "active"
        user.password_hash = hash_password(initial_password(item["phone"]))
        user.password_status = "initial"
        if not user.oss_account:
            user.oss_password_cipher = None
            user.oss_bind_status = "unbound"

    removed = []
    for user in plan["current"]:
        if user.id in keep_ids:
            continue
        removed.append({"id": user.id, "mobile": user.mobile, "oss_account": user.oss_account, "role": user.role_code})
        delete_user_relations(user.id)
        db.session.delete(user)
    db.session.commit()
    sync_collector_mappings(orgs)
    return {
        "matched_by_mobile": matched,
        "inserted": inserted,
        "retained_oss": retained_oss,
        "removed": removed,
    }


def verify(expected_count, break_glass_account):
    total = User.query.count()
    oa_total = User.query.filter(User.oa_username.isnot(None)).count()
    normal_oa = User.query.filter(User.oa_username.isnot(None), User.role_code == "normal_user").count()
    initial_oa = User.query.filter(User.oa_username.isnot(None), User.password_status == "initial").count()
    internal_oa = User.query.filter(User.oa_username.isnot(None), User.user_type == "internal").count()
    org_missing = User.query.filter(User.oa_username.isnot(None), User.org_id.is_(None)).count()
    break_glass = User.query.filter((User.mobile == break_glass_account) | (User.oss_account == break_glass_account)).first()
    checks = {
        "oa_total": oa_total == expected_count,
        "oa_all_normal": normal_oa == expected_count,
        "oa_all_initial_password": initial_oa == expected_count,
        "oa_all_internal": internal_oa == expected_count,
        "oa_all_have_org": org_missing == 0,
        "break_glass_active": bool(break_glass and break_glass.role_code == "super_admin" and break_glass.status == "active"),
    }
    return {
        "users_total": total,
        "oa_users": oa_total,
        "oss_bound_or_present": User.query.filter(User.oa_username.isnot(None), User.oss_account.isnot(None)).count(),
        "checks": checks,
        "passed": all(checks.values()),
    }


def drop_source_tables(expected_count):
    if User.query.filter(User.oa_username.isnot(None)).count() != expected_count:
        raise RuntimeError("OA 用户数量未达到预期，拒绝清理源表")
    db.session.execute(text("DROP TABLE users_from_oa"))
    db.session.execute(text("DROP TABLE sys_area_org_mapping"))
    db.session.commit()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--drop-source-tables", action="store_true")
    parser.add_argument("--drop-source-tables-only", action="store_true")
    parser.add_argument("--break-glass-account", default="admin")
    parser.add_argument("--audit-dir", default="/home/yvesyuan/deploy/backups/oa-user-migration")
    args = parser.parse_args()
    with app.app_context():
        if args.drop_source_tables_only:
            verification = verify(1641, args.break_glass_account)
            if not verification["passed"]:
                raise RuntimeError(f"清理前校验失败: {verification}")
            drop_source_tables(1641)
            report = {
                "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                "mode": "drop-source-tables-only",
                "verification": verification,
                "source_tables_dropped": True,
            }
            audit_dir = Path(args.audit_dir)
            audit_dir.mkdir(parents=True, exist_ok=True)
            audit_file = audit_dir / f"oa-user-source-cleanup-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
            audit_file.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
            print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
            print(f"审计文件: {audit_file}")
            return
        source, mappings = load_source()
        plan = preflight(source, mappings, args.break_glass_account)
        if plan["errors"]:
            raise RuntimeError("预检失败:\n- " + "\n- ".join(plan["errors"]))
        root, orgs, created, renamed = resolve_orgs(plan, args.apply)
        report = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "mode": "apply" if args.apply else "dry-run",
            "source_total": len(source),
            "excluded_admin_test_users": [item["username"] for item in plan["excluded"]],
            "valid_oa_users": len(plan["valid"]),
            "matched_by_mobile_planned": sum(1 for item in plan["valid"] if plan["users_by_phone"].get(item["phone"])),
            "new_users_planned": sum(1 for item in plan["valid"] if not plan["users_by_phone"].get(item["phone"])),
            "old_users_to_remove_planned": sum(1 for user in plan["current"] if user.id != plan["break_glass"].id and normalized_mobile(user.mobile) not in {item["phone"] for item in plan["valid"]}),
            "break_glass_user_id": plan["break_glass"].id,
            "cross_namespace_login_collisions": plan["identity_collisions"],
            "organizations_to_create": created,
            "organizations_to_rename": renamed,
        }
        if args.apply:
            report["migration"] = migrate(plan, orgs, root)
            report["verification"] = verify(len(plan["valid"]), args.break_glass_account)
            if not report["verification"]["passed"]:
                raise RuntimeError(f"迁移后校验失败: {report['verification']}")
            if args.drop_source_tables:
                drop_source_tables(len(plan["valid"]))
                report["source_tables_dropped"] = True
        audit_dir = Path(args.audit_dir)
        audit_dir.mkdir(parents=True, exist_ok=True)
        audit_file = audit_dir / f"oa-user-migration-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
        audit_file.write_text(json.dumps(report, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
        print(f"审计文件: {audit_file}")


if __name__ == "__main__":
    main()
