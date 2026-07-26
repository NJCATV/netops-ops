"""使用应用现有 DATABASE_URL 生成迁移前 MySQL 全库逻辑备份，不输出凭据。"""

from datetime import datetime, timezone
import gzip
import hashlib
import os
from pathlib import Path
import subprocess

from sqlalchemy.engine import make_url

from app.config import Config


target_dir = Path("/home/yvesyuan/deploy/backups/oa-user-migration")
target_dir.mkdir(parents=True, exist_ok=True)
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
target = target_dir / f"anbo_wx-before-oa-migration-{stamp}.sql.gz"
url = make_url(Config.SQLALCHEMY_DATABASE_URI)
database = url.database or "anbo_wx"
command = [
    "mysqldump",
    "--single-transaction",
    "--quick",
    "--routines",
    "--triggers",
    "--events",
    "--set-gtid-purged=OFF",
    "--default-character-set=utf8mb4",
    "--host", url.host or "127.0.0.1",
    "--port", str(url.port or 3306),
    "--user", url.username or "",
    database,
]
environment = os.environ.copy()
environment["MYSQL_PWD"] = url.password or ""
with target.open("wb") as raw:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    assert process.stdout is not None
    with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=6) as compressed:
        while chunk := process.stdout.read(1024 * 1024):
            compressed.write(chunk)
    stderr = process.stderr.read().decode("utf-8", "replace") if process.stderr else ""
    code = process.wait()
if code:
    target.unlink(missing_ok=True)
    raise RuntimeError(f"mysqldump 失败: {stderr.strip()}")
with gzip.open(target, "rb") as stream:
    while stream.read(1024 * 1024):
        pass
digest = hashlib.sha256(target.read_bytes()).hexdigest()
checksum = target.with_suffix(target.suffix + ".sha256")
checksum.write_text(f"{digest}  {target.name}\n", encoding="ascii")
print(f"备份完成: {target}")
print(f"SHA-256: {digest}")
