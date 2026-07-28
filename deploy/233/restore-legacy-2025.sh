#!/usr/bin/env bash
set -Eeuo pipefail

# Restore the preserved Vue2 NetAlert UI under /2025/ and isolate its legacy
# Flask API on 127.0.0.1:7003.  The current NetOps BFF remains on 7001.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo 'Run with sudo.' >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DIST_ROOT=/srv/netops/netops-portal-web/dist
LEGACY_SOURCE=/var/www/NetAlert/frontend/dist/2025
NGINX_FILE=/etc/nginx/sites-enabled/netalert_frontend.conf
SERVICE_FILE=/etc/systemd/system/netops-legacy-api.service
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/var/backups/netops-legacy-2025/$STAMP

for path in "$DIST_ROOT" "$LEGACY_SOURCE/index.html" "$LEGACY_SOURCE/static/js/app.cfbff342.js" "$NGINX_FILE" "$SCRIPT_DIR/netops-legacy-api.service"; do
  [[ -e "$path" ]] || { echo "Missing required path: $path" >&2; exit 1; }
done

mkdir -p "$BACKUP_DIR"
cp -a "$NGINX_FILE" "$BACKUP_DIR/netalert_frontend.conf.before"
[[ -e "$SERVICE_FILE" ]] && cp -a "$SERVICE_FILE" "$BACKUP_DIR/netops-legacy-api.service.before" || true

rollback_nginx() {
  cp -a "$BACKUP_DIR/netalert_frontend.conf.before" "$NGINX_FILE"
  nginx -t && systemctl reload nginx || true
}

# A portal release must never overwrite the original legacy package.  Replace
# only when this is not the known Vue2 package.
if [[ ! -f "$DIST_ROOT/2025/static/js/app.cfbff342.js" ]]; then
  stage="$DIST_ROOT/.2025-restore-$STAMP"
  mkdir "$stage"
  cp -a "$LEGACY_SOURCE/." "$stage/"
  [[ -d "$DIST_ROOT/2025" ]] && mv "$DIST_ROOT/2025" "$BACKUP_DIR/2025.before"
  mv "$stage" "$DIST_ROOT/2025"
fi

python3 - "$NGINX_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start = text.find("    location /api/ {")
if start < 0:
    raise SystemExit("generic /api/ location is missing")
end = text.find("    # ④", start)
if end < 0:
    raise SystemExit("cannot determine generic /api/ location boundary")
block = text[start:end]
old = "proxy_pass http://127.0.0.1:7001;"
new = "proxy_pass http://127.0.0.1:7003;  # legacy /2025 API only; new API prefixes match earlier locations"
if new not in block:
    if old not in block:
        raise SystemExit("unexpected generic /api/ upstream; refusing to change it")
    block = block.replace(old, new, 1)
    text = text[:start] + block + text[end:]
    path.write_text(text, encoding="utf-8")
PY

if ! nginx -t; then
  rollback_nginx
  exit 1
fi

install -m 0644 "$SCRIPT_DIR/netops-legacy-api.service" "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable --now netops-legacy-api.service

if [[ $(curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:7003/api/admin/login -H 'Content-Type: application/json' -d '{}') != 400 ]]; then
  echo 'Legacy API health probe failed.' >&2
  systemctl disable --now netops-legacy-api.service || true
  rollback_nginx
  exit 1
fi
if [[ $(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:7001/api/netops2026/auth/me) != 401 ]]; then
  echo 'Current BFF regression probe failed.' >&2
  rollback_nginx
  exit 1
fi

systemctl reload nginx
legacy_code=$(curl -k -sS -o /dev/null -w '%{http_code}' --resolve 172.31.1.233:5772:127.0.0.1 https://172.31.1.233:5772/2025/)
legacy_login_code=$(curl -k -sS -o /dev/null -w '%{http_code}' -X POST --resolve 172.31.1.233:5772:127.0.0.1 https://172.31.1.233:5772/api/admin/login -H 'Content-Type: application/json' -d '{}')
[[ "$legacy_code" == 200 && "$legacy_login_code" == 400 ]] || { echo "Legacy public probes failed: ui=$legacy_code login=$legacy_login_code" >&2; exit 1; }

echo "Legacy 2025 restored; backup: $BACKUP_DIR"
