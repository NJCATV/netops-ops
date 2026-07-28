#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo "run with sudo as root" >&2; exit 1; }

NGINX=/etc/nginx/sites-enabled/netalert_frontend.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/netops-admin-route/$STAMP

mkdir -p "$BACKUP"
cp -a "$NGINX" "$BACKUP/netalert_frontend.conf.before"

rollback() {
  cp -a "$BACKUP/netalert_frontend.conf.before" "$NGINX"
  nginx -t && systemctl reload nginx || true
}
trap rollback ERR

python3 - "$NGINX" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "    location ^~ /api/netops2026/ {"
block = """    # Current platform administration API. Keep this inside the
    # /api/netops2026 namespace because preserved /2025 routes own /api/admin.
    location ^~ /api/netops2026/admin/ {
        limit_req zone=api_limit burst=20 nodelay;
        add_header X-NetOps-API-Proxy hit always;
        proxy_pass http://127.0.0.1:7001/api/admin/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Authorization     $http_authorization;
        proxy_connect_timeout 30;
        proxy_read_timeout    120;
        proxy_send_timeout    120;
    }

"""
if "location ^~ /api/netops2026/admin/" not in text:
    if marker not in text:
        raise SystemExit("current NetOps API location is missing")
    text = text.replace(marker, block + marker, 1)
    path.write_text(text, encoding="utf-8")
PY

nginx -t
systemctl reload nginx

new_code=$(curl -k -sS -o /dev/null -w '%{http_code}' \
  --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' \
  https://anbo.njcatv.net:5772/api/netops2026/admin/menus)
legacy_code=$(curl -k -sS -o /dev/null -w '%{http_code}' -X POST \
  --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' \
  https://anbo.njcatv.net:5772/api/admin/login \
  -H 'Content-Type: application/json' -d '{}')

if [[ "$new_code" != 401 ]]; then
  echo "current admin API probe failed: $new_code" >&2
  curl -ki --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' \
    https://anbo.njcatv.net:5772/api/netops2026/admin/menus | head -n 20 >&2
  nginx -T 2>&1 | grep -A18 -B2 'location .~ /api/netops2026/admin/' >&2 || true
  exit 1
fi
[[ "$legacy_code" == 400 ]] || { echo "legacy login probe failed: $legacy_code" >&2; exit 1; }

trap - ERR
echo "admin route repaired; backup=$BACKUP"
