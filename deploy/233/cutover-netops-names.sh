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
# The generic legacy proxy would collide with the existing unrelated /api/ socket.
t, removed = re.subn(r'\n\s*location \^~ /wx/api/ \{.*?\n\s*\}\n', '\n', t, count=1, flags=re.S)
if removed != 1 or '/wx/api' in t or '/srv/netops/netops-portal-web/dist;' not in t:
    raise SystemExit('Nginx normalization verification failed')
p.write_text(t)
PY

nginx -t
systemctl daemon-reload
systemctl disable --now zhiwei-api.service
systemctl enable --now netops-platform-api.service
systemctl is-active --quiet netops-platform-api.service
systemctl reload nginx
curl -kfsS -H 'Host: anbo.njcatv.net' https://127.0.0.1:5772/api/health >/dev/null
if curl -kfsS -H 'Host: anbo.njcatv.net' https://127.0.0.1:5772/wx/api/health >/dev/null; then
  echo 'obsolete /wx route is still reachable' >&2
  exit 1
fi
trap - ERR
echo "cutover complete: backup=$BACKUP"
