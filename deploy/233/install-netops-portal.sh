#!/usr/bin/env bash
set -Eeuo pipefail

# 将新版智维平台切换为 5772 根入口，并把原根目录旧版迁移到 /2025/。
# 只修改前端静态文件与 Nginx 路由，不重启旧版 API、Celery 或 netops-platform-api。
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR=${1:-$SCRIPT_DIR/root-dist}
DIST_ROOT=/var/www/NetAlert/frontend/dist
NGINX_FILE=/etc/nginx/sites-enabled/netalert_frontend.conf
LOCATION_FILE=$SCRIPT_DIR/nginx-root-entry-locations.conf
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR=/var/backups/zhiwei-root-entry/$STAMP
NGINX_CHANGED=0
INDEX_CHANGED=0

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "错误：请使用 sudo 执行本脚本。" >&2
  exit 1
fi

for path in "$BUILD_DIR/index.html" "$BUILD_DIR/assets" "$BUILD_DIR/brand" "$DIST_ROOT/index.html" "$NGINX_FILE" "$LOCATION_FILE"; do
  if [[ ! -e "$path" ]]; then
    echo "错误：缺少 $path" >&2
    exit 1
  fi
done

if grep -q '/2026/assets/' "$BUILD_DIR/index.html"; then
  echo "错误：构建产物仍使用 /2026/ 基础路径，拒绝切换根入口。" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
cp -a "$NGINX_FILE" "$BACKUP_DIR/netalert_frontend.conf.before"
cp -a "$DIST_ROOT/index.html" "$BACKUP_DIR/index.html.before"
[[ -d "$DIST_ROOT/assets" ]] && cp -a "$DIST_ROOT/assets" "$BACKUP_DIR/assets.before"

rollback() {
  rc=$?
  if [[ $rc -eq 0 ]]; then return; fi
  echo "切换失败，正在恢复根首页和 Nginx 配置；备份：$BACKUP_DIR" >&2
  cp -a "$BACKUP_DIR/index.html.before" "$DIST_ROOT/index.html"
  cp -a "$BACKUP_DIR/netalert_frontend.conf.before" "$NGINX_FILE"
  nginx -t && systemctl reload nginx || true
  exit "$rc"
}
trap rollback ERR

fail() {
  echo "$1" >&2
  return 1
}

# 首次执行时固定保存旧版，不在重复发布时覆盖 /2025/。
if [[ ! -f "$DIST_ROOT/2025/index.html" ]]; then
  LEGACY_STAGE="$DIST_ROOT/.2025-stage-$STAMP"
  mkdir -p "$LEGACY_STAGE"
  cp -a "$DIST_ROOT/index.html" "$LEGACY_STAGE/index.html"
  [[ -d "$DIST_ROOT/static" ]] && cp -a "$DIST_ROOT/static" "$LEGACY_STAGE/static"
  [[ -f "$DIST_ROOT/jscn.jpg" ]] && cp -a "$DIST_ROOT/jscn.jpg" "$LEGACY_STAGE/jscn.jpg"
  [[ -f "$DIST_ROOT/favicon.ico" ]] && cp -a "$DIST_ROOT/favicon.ico" "$LEGACY_STAGE/favicon.ico"
  python3 - "$LEGACY_STAGE" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for path in [root / "index.html", *root.rglob("*.js"), *root.rglob("*.css")]:
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    text = text.replace('o.p="/"', 'o.p="/2025/"')
    text = text.replace('href=/static/', 'href=/2025/static/')
    text = text.replace('src=/static/', 'src=/2025/static/')
    text = text.replace('url(/static/', 'url(/2025/static/')
    text = text.replace('href=/jscn.jpg', 'href=/2025/jscn.jpg')
    path.write_text(text, encoding="utf-8")
PY
  mv "$LEGACY_STAGE" "$DIST_ROOT/2025"
fi

# 新版构建复制到根目录；保留 /2025、/2026/legacy-aiops、uploads 与旧 API 静态依赖。
cp -a "$BUILD_DIR/assets" "$DIST_ROOT/"
cp -a "$BUILD_DIR/brand" "$DIST_ROOT/"
cp -a "$BUILD_DIR/index.html" "$DIST_ROOT/index.html"
chown -R yvesyuan:yvesyuan "$DIST_ROOT/assets" "$DIST_ROOT/brand" "$DIST_ROOT/index.html" "$DIST_ROOT/2025"
INDEX_CHANGED=1

if ! grep -Eq 'location[[:space:]]+\^~[[:space:]]+/2025/' "$NGINX_FILE"; then
  python3 - "$NGINX_FILE" "$LOCATION_FILE" <<'PY'
from pathlib import Path
import re
import sys

target = Path(sys.argv[1])
snippet = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = target.read_text(encoding="utf-8")
indented = "\n".join("    " + line if line else "" for line in snippet.splitlines()) + "\n"
pattern = re.compile(r"(?ms)^[ \t]*location[ \t]+\^~[ \t]+/2026/[ \t]*\{.*?^[ \t]*\}[ \t]*\n")
if pattern.search(text):
    text = pattern.sub(indented, text, count=1)
else:
    marker = "    location / {"
    if marker not in text:
        raise SystemExit("未找到 /2026/ location 或根 location，拒绝修改")
    text = text.replace(marker, indented + "\n" + marker, 1)
target.write_text(text, encoding="utf-8")
PY
  NGINX_CHANGED=1
fi

nginx -t
systemctl reload nginx

ROOT_TMP=$(mktemp)
LEGACY_TMP=$(mktemp)
trap 'rm -f "$ROOT_TMP" "$LEGACY_TMP"' EXIT
ROOT_CODE=$(curl -k -sS -H 'Host: anbo.njcatv.net' -o "$ROOT_TMP" -w '%{http_code}' https://127.0.0.1:5772/nonexistent-route)
LEGACY_CODE=$(curl -k -sS -H 'Host: anbo.njcatv.net' -o "$LEGACY_TMP" -w '%{http_code}' https://127.0.0.1:5772/2025/)
REDIRECT_RESULT=$(curl --noproxy '*' -k -sS -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Host: anbo.njcatv.net' https://127.0.0.1:5772/2026/)
read -r REDIRECT_CODE REDIRECT_URL <<<"$REDIRECT_RESULT"
API_CODE=$(curl -k -sS -H 'Host: anbo.njcatv.net' -o /dev/null -w '%{http_code}' https://127.0.0.1:5772/api/netops2026/auth/me)

if [[ "$ROOT_CODE" != "200" ]] || ! cmp -s "$ROOT_TMP" "$DIST_ROOT/index.html"; then
  fail "验收失败：新版根入口或 SPA 回退异常（HTTP $ROOT_CODE）。"
fi
if [[ "$LEGACY_CODE" != "200" ]] || ! cmp -s "$LEGACY_TMP" "$DIST_ROOT/2025/index.html"; then
  fail "验收失败：/2025/ 旧版入口异常（HTTP $LEGACY_CODE）。"
fi
if [[ "$REDIRECT_CODE" != "301" ]]; then
  fail "验收失败：/2026/ 未返回 301（实际 HTTP $REDIRECT_CODE）。"
fi
if [[ ! "$REDIRECT_URL" =~ ^https://(anbo\.njcatv\.net|172\.31\.1\.233):5772/$ ]]; then
  fail "验收失败：/2026/ 跳转目标不是新版根入口（$REDIRECT_URL）。"
fi
if [[ "$API_CODE" != "401" ]]; then
  fail "验收失败：未登录 API 探针预期 401，实际 HTTP $API_CODE。"
fi

trap - ERR
echo "根入口切换成功。"
echo "新版：https://172.31.1.233:5772/"
echo "旧版：https://172.31.1.233:5772/2025/"
echo "兼容跳转：/2026/ -> /"
echo "API 探针：HTTP $API_CODE"
echo "备份目录：$BACKUP_DIR"
