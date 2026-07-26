#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BACKEND_SOURCE=${1:-/home/yvesyuan/deploy/netops2026-quality-optimized.py}
BACKEND_TARGET=/home/yvesyuan/PycharmProjects/anbo_wx/backend/app/routes/netops2026.py
VENV=/home/yvesyuan/PycharmProjects/anbo_wx/backend/.venv
CACHE_WARMER_SOURCE=$SCRIPT_DIR/warm_quality_cache.py
CACHE_WARMER_TARGET=/home/yvesyuan/deploy/quality-cache-warmer.py
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/var/backups/zhiwei-quality-performance/$STAMP

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "请使用 sudo 执行。" >&2
  exit 1
fi

for path in "$BACKEND_SOURCE" "$BACKEND_TARGET" "$VENV/bin/python" "$SCRIPT_DIR/install-zhiwei-root-entry.sh" \
  "$CACHE_WARMER_SOURCE" "$SCRIPT_DIR/zhiwei-quality-cache.service" "$SCRIPT_DIR/zhiwei-quality-cache.timer"; do
  [[ -e "$path" ]] || { echo "缺少文件：$path" >&2; exit 1; }
done

mkdir -p "$BACKUP_DIR"
cp -a "$BACKEND_TARGET" "$BACKUP_DIR/netops2026.py.before"

rollback() {
  rc=$?
  [[ $rc -eq 0 ]] && return
  echo "发布失败，恢复 API 文件；备份：$BACKUP_DIR" >&2
  cp -a "$BACKUP_DIR/netops2026.py.before" "$BACKEND_TARGET"
  "$VENV/bin/python" -m py_compile "$BACKEND_TARGET" || true
  systemctl show -p MainPID --value zhiwei-api.service | xargs -r kill -HUP || true
  exit "$rc"
}
trap rollback ERR

install -o yvesyuan -g yvesyuan -m 0644 "$BACKEND_SOURCE" "$BACKEND_TARGET"
"$VENV/bin/python" -m py_compile "$BACKEND_TARGET"
systemctl show -p MainPID --value zhiwei-api.service | xargs -r kill -HUP
sleep 2
systemctl is-active --quiet zhiwei-api.service
curl --noproxy '*' -fsS http://127.0.0.1:7001/api/health >/dev/null

bash "$SCRIPT_DIR/install-zhiwei-root-entry.sh"

install -o yvesyuan -g yvesyuan -m 0755 "$CACHE_WARMER_SOURCE" "$CACHE_WARMER_TARGET"
install -o root -g root -m 0644 "$SCRIPT_DIR/zhiwei-quality-cache.service" /etc/systemd/system/zhiwei-quality-cache.service
install -o root -g root -m 0644 "$SCRIPT_DIR/zhiwei-quality-cache.timer" /etc/systemd/system/zhiwei-quality-cache.timer
systemctl daemon-reload
systemctl enable --now zhiwei-quality-cache.timer

API_CODE=$(curl --noproxy '*' -k -sS -o /dev/null -w '%{http_code}' -H 'Host: anbo.njcatv.net' \
  https://127.0.0.1:5772/wx/api/netops2026/auth/me)
[[ "$API_CODE" == "401" ]]

trap - ERR
echo "质差查询与自适应布局发布成功。"
echo "备份目录：$BACKUP_DIR"
