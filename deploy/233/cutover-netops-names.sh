#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'run with sudo as root' >&2; exit 1; }

OWNER=yvesyuan
SOURCE=/home/yvesyuan/netops-staging
TARGET=/srv/netops
OLD=/home/yvesyuan/PycharmProjects/anbo_wx
NGINX=/etc/nginx/sites-enabled/netalert_frontend.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=/var/backups/netops/naming-cutover-$STAMP

for file in "$SOURCE/netops-ops/deploy/233/netops-platform-api.service" "$SOURCE/netops-portal-web/dist/index.html" "$SOURCE/netops-platform-api/platform-adapter/host-application/backend/app/routes/netops2026.py" "$SOURCE/netops-littleProgram/backend/run.py" "$OLD/backend/.env" "$OLD/backend/.venv/bin/python" "$NGINX"; do
  [[ -e "$file" ]] || { echo "required file missing: $file" >&2; exit 1; }
done

mkdir -p "$BACKUP" "$TARGET" /etc/netops
cp -a "$NGINX" "$BACKUP/netalert_frontend.conf.before"
cp -a /etc/systemd/system/zhiwei-api.service "$BACKUP/zhiwei-api.service.before"

rollback() {
  cp -af "$BACKUP/netalert_frontend.conf.before" "$NGINX"
  cp -af "$BACKUP/zhiwei-api.service.before" /etc/systemd/system/zhiwei-api.service
  systemctl daemon-reload || true
  systemctl disable --now netops-platform-api.service || true
  systemctl enable --now zhiwei-api.service || true
  nginx -t && systemctl reload nginx || true
}
trap rollback ERR

for repo in netops-portal-web netops-platform-api netops-littleProgram; do
  if [[ -e "$TARGET/$repo" ]]; then
    mv "$TARGET/$repo" "$BACKUP/$repo.before"
  fi
  cp -a "$SOURCE/$repo" "$TARGET/$repo"
  chown -R "$OWNER:www-data" "$TARGET/$repo"
done

cp -a "$TARGET/netops-platform-api/platform-adapter/host-application/backend/app/routes/netops2026.py" "$TARGET/netops-littleProgram/backend/app/routes/netops2026.py"
cp -a "$OLD/backend/.venv" "$TARGET/netops-littleProgram/backend/.venv"
install -d -m 0750 -o "$OWNER" -g www-data "$TARGET/netops-littleProgram/backend/uploads" "$TARGET/netops-littleProgram/backend/logs"
install -m 0640 -o root -g www-data "$OLD/backend/.env" /etc/netops/netops-littleProgram.env
install -m 0644 "$SOURCE/netops-ops/deploy/233/netops-platform-api.service" /etc/systemd/system/netops-platform-api.service

python3 - "$NGINX" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text()
for old, new in {
    'location = /wx/api/auth/login {': 'location = /api/auth/login {',
    'location = /wx/api/netops2026/onu/search {': 'location = /api/netops2026/onu/search {',
    'location ^~ /wx/api/netops2026/boss/ {': 'location ^~ /api/netops2026/boss/ {',
    'wx_login': 'netops_login', 'wx_onu_search': 'netops_onu_search',
    'wx_boss': 'netops_boss', 'X-WX-API-Proxy': 'X-NetOps-API-Proxy',
    'root  /var/www/NetAlert/frontend/dist;': 'root  /srv/netops/netops-portal-web/dist;',
}.items():
    t = t.replace(old, new)
# Retain NetOps' generic route, but make it more specific than the unrelated /api/ socket.
t = t.replace('location ^~ /wx/api/ {', 'location ^~ /api/netops2026/ {')
t = t.replace('proxy_pass http://127.0.0.1:7001/api/;', 'proxy_pass http://127.0.0.1:7001/api/netops2026/;', 1)
# The generic /api/ block belongs to the same Flask BFF.  Leaving it on the
# historical newalert socket makes portal administration endpoints return 404.
t = t.replace('proxy_pass http://unix:/tmp/gunicorn_newalertadmin.sock:/api/;', 'proxy_pass http://127.0.0.1:7001;', 1)
legacy_block = '''    # 已废弃的微信小程序入口；禁止回退到 SPA 首页，避免旧客户端悄然继续使用。
    location = /wx {
        return 410;
    }

    location ^~ /wx/ {
        return 410;
    }

'''
spa_marker = '    # ② 单页应用入口（前端页面 + 限流）\n'
if 'location ^~ /wx/' not in t:
    if spa_marker not in t:
        raise SystemExit('Nginx SPA marker missing; refusing to insert legacy-route block')
    t = t.replace(spa_marker, legacy_block + spa_marker, 1)
if re.search(r'^[ \t]*location\b[^\n]*?/wx/api', t, flags=re.M) or 'location ^~ /api/netops2026/' not in t or 'location ^~ /wx/' not in t or '/srv/netops/netops-portal-web/dist;' not in t or 'proxy_pass http://unix:/tmp/gunicorn_newalertadmin.sock:/api/;' in t:
    raise SystemExit('Nginx normalization verification failed')
p.write_text(t)
PY

nginx -t
systemctl daemon-reload
systemctl disable --now zhiwei-api.service
systemctl enable --now netops-platform-api.service
systemctl is-active --quiet netops-platform-api.service
systemctl reload nginx
for _ in {1..10}; do
  code=$(curl -k -s -o /dev/null -w '%{http_code}' --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' https://anbo.njcatv.net:5772/api/netops2026/auth/me)
  [[ "$code" == 401 ]] && break
  sleep 1
done
[[ "$code" == 401 ]] || { echo "unexpected NetOps API status: $code" >&2; exit 1; }
admin_code=$(curl -k -s -o /dev/null -w '%{http_code}' --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' https://anbo.njcatv.net:5772/api/admin/menus)
[[ "$admin_code" == 401 ]] || { echo "unexpected admin API status: $admin_code" >&2; exit 1; }
for _ in {1..10}; do
  legacy_code=$(curl -k -s -o /dev/null -w '%{http_code}' --resolve anbo.njcatv.net:5772:127.0.0.1 -A 'NetOps-HealthCheck/1.0' https://anbo.njcatv.net:5772/wx/api/health)
  [[ "$legacy_code" == 410 ]] && break
  sleep 1
done
[[ "$legacy_code" == 410 ]] || { echo "obsolete /wx route returned: $legacy_code" >&2; exit 1; }
trap - ERR
echo "cutover complete: backup=$BACKUP"
