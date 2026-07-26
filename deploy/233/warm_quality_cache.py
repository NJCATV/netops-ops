#!/usr/bin/env python3
"""Warm the default ONU quality list and summary through the production API."""

from datetime import datetime
import json
from pathlib import Path
import sys
import time
from urllib import request

BACKEND_ROOT = Path("/home/yvesyuan/PycharmProjects/anbo_wx/backend")
sys.path.insert(0, str(BACKEND_ROOT))

from app import create_app
from app.models import User
from app.utils.jwt import create_access_token


def fetch(url, token):
    started = time.perf_counter()
    req = request.Request(url, headers={"Authorization": f"Bearer {token}", "Host": "anbo.njcatv.net"})
    with request.urlopen(req, timeout=180) as response:
        body = response.read()
        payload = json.loads(body)
        if response.status != 200 or payload.get("code") not in (0, 200):
            raise RuntimeError(f"cache warm failed: HTTP {response.status}, code={payload.get('code')}")
    return round(time.perf_counter() - started, 3), len(body)


def main():
    app = create_app()
    with app.app_context():
        user = User.query.filter_by(role_code="super_admin", status="active").order_by(User.id).first()
        if user is None:
            raise RuntimeError("no active super_admin available for internal cache warming")
        token = create_access_token(user.id)

    date = datetime.now().strftime("%Y-%m-%d")
    base = "http://127.0.0.1:7001/api/netops2026/onu/quality-daily"
    common = f"date={date}&quality_code=&include_unknown_ports=0&trend_days=30&no_cache=1"
    cases = (
        ("table", f"{base}?page=1&size=20&summary=0&{common}"),
        ("summary", f"{base}?page=1&size=20&summary=1&summary_only=1&{common}"),
    )
    for name, url in cases:
        seconds, size = fetch(url, token)
        print(f"quality_cache_warm name={name} seconds={seconds} bytes={size}", flush=True)


if __name__ == "__main__":
    main()
