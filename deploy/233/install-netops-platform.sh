#!/usr/bin/env bash
set -Eeuo pipefail

# 在 JSCN-233 上以 root 执行。脚本只切换 anbo_wx:7001 和 /2026/，
# 不会重启 newalertadmin、Celery，也不会修改旧版 5772/ 与 5772/api/。

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BACKEND=/srv/netops/netops-littleProgram/backend
SERVICE_FILE=/etc/systemd/system/netops-platform-api.service
NGINX_FILE=/etc/nginx/sites-enabled/netalert_frontend.conf
NGINX_SNIPPET_FILE=$SCRIPT_DIR/nginx-2026-location.conf
UNIT_SOURCE=$SCRIPT_DIR/netops-platform-api.service
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/var/backups/zhiwei-production/$STAMP
OLD_START=$BACKEND/start-netops7001.sh
OLD_PIDFILE=$BACKEND/logs/netops7001.pid
CRON_BEFORE=$BACKUP_DIR/yvesyuan.crontab.before
CRON_AFTER=$BACKUP_DIR/yvesyuan.crontab.after
NGINX_CHANGED=0
SERVICE_STARTED=0

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "错误：请使用 sudo 执行本脚本。" >&2
  exit 1
fi

for path in "$BACKEND" "$UNIT_SOURCE" "$NGINX_SNIPPET_FILE" "$NGINX_FILE"; do
  if [[ ! -e "$path" ]]; then
    echo "错误：缺少 $path" >&2
    exit 1
  fi
done

if [[ ! -x "$BACKEND/.venv/bin/gunicorn" ]]; then
  echo "错误：anbo_wx 虚拟环境中未安装 gunicorn。" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp -a "$NGINX_FILE" "$BACKUP_DIR/netalert_frontend.conf.before"
if [[ -f "$SERVICE_FILE" ]]; then
  cp -a "$SERVICE_FILE" "$BACKUP_DIR/netops-platform-api.service.before"
fi
crontab -u yvesyuan -l >"$CRON_BEFORE" 2>/dev/null || :

rollback() {
  rc=$?
  if [[ $rc -eq 0 ]]; then
    return
  fi
  echo "切换失败，开始回滚（备份：$BACKUP_DIR）" >&2
  systemctl stop netops-platform-api.service 2>/dev/null || true
  if [[ $NGINX_CHANGED -eq 1 ]]; then
    cp -a "$BACKUP_DIR/netalert_frontend.conf.before" "$NGINX_FILE"
    nginx -t && systemctl reload nginx || true
  fi
  crontab -u yvesyuan "$CRON_BEFORE" 2>/dev/null || true
  if ! ss -ltn 'sport = :7001' | grep -q LISTEN && [[ -x "$OLD_START" ]]; then
    runuser -u yvesyuan -- "$OLD_START" || true
  fi
  exit "$rc"
}
trap rollback ERR

install -o root -g root -m 0644 "$UNIT_SOURCE" "$SERVICE_FILE"
systemd-analyze verify "$SERVICE_FILE"

if ! grep -Eq 'location[[:space:]]+\^~[[:space:]]+/2026/' "$NGINX_FILE"; then
  python3 - "$NGINX_FILE" "$NGINX_SNIPPET_FILE" <<'PY'
from pathlib import Path
import sys

target = Path(sys.argv[1])
snippet = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = target.read_text(encoding="utf-8")
marker = "    # ② 单页应用入口（前端页面 + 限流）"
if marker not in text:
    marker = "    location / {"
if marker not in text:
    raise SystemExit("未找到安全插入 /2026/ location 的位置")
indented = "\n".join("    " + line if line else "" for line in snippet.splitlines())
target.write_text(text.replace(marker, indented + "\n\n" + marker, 1), encoding="utf-8")
PY
  NGINX_CHANGED=1
fi
nginx -t

# 只允许终止 anbo_wx/backend 下的临时 run.py，避免误伤其他 Python 项目。
TEMP_PID=$(ss -ltnp 'sport = :7001' 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -1)
if [[ -n "$TEMP_PID" ]]; then
  TEMP_CWD=$(readlink -f "/proc/$TEMP_PID/cwd" || true)
  TEMP_CMD=$(tr '\0' ' ' <"/proc/$TEMP_PID/cmdline" || true)
  if [[ "$TEMP_CWD" != "$BACKEND" || "$TEMP_CMD" != *"run.py"* ]]; then
    echo "错误：7001 被非预期进程占用：PID=$TEMP_PID CWD=$TEMP_CWD CMD=$TEMP_CMD" >&2
    exit 1
  fi
  kill -TERM "$TEMP_PID"
  for _ in {1..40}; do
    kill -0 "$TEMP_PID" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$TEMP_PID" 2>/dev/null; then
    echo "错误：临时进程未能优雅退出。" >&2
    exit 1
  fi
fi
rm -f "$OLD_PIDFILE"

# 删除旧的 @reboot 临时启动项，避免重启后与 systemd 抢占 7001。
awk '!/start-netops7001\.sh/ && !/codex-netops7001/' "$CRON_BEFORE" >"$CRON_AFTER"
crontab -u yvesyuan "$CRON_AFTER"

systemctl daemon-reload
systemctl enable --now netops-platform-api.service
SERVICE_STARTED=1
systemctl reload nginx

sleep 3
systemctl is-active --quiet netops-platform-api.service
systemctl is-enabled --quiet netops-platform-api.service

API_CODE=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:7001/api/auth/me)
if [[ "$API_CODE" != "401" ]]; then
  echo "错误：API 探针预期 401，实际为 $API_CODE。" >&2
  exit 1
fi

SPA_TMP=$(mktemp)
trap 'rm -f "$SPA_TMP"' EXIT
SPA_CODE=$(curl -k -sS -H 'Host: anbo.njcatv.net' -o "$SPA_TMP" -w '%{http_code}' \
  https://127.0.0.1:5772/2026/nonexistent-route)
if [[ "$SPA_CODE" != "200" ]] || ! cmp -s "$SPA_TMP" /var/www/NetAlert/frontend/dist/2026/index.html; then
  echo "错误：/2026/ SPA 回退验证失败。" >&2
  exit 1
fi

trap - ERR
echo "切换成功。"
echo "备份目录：$BACKUP_DIR"
systemctl --no-pager --full status netops-platform-api.service | head -25
ss -ltnp 'sport = :7001'
echo "/2026/ SPA fallback: HTTP $SPA_CODE，内容与新版 index.html 一致"
