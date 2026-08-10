#!/usr/bin/env bash
#
# 真机数据库备份脚本（部署/升级前的必做第一步）
#
# 序列：run-as 前置探测 → force-stop → WAL 三件套 exec-out 拉取 →
#       本地 checkpoint(TRUNCATE) → 三重校验（integrity / user_version / 行数）
#
# ⚠️ WAL 侧车纪律：必须三件套（contexta.db + -wal + -shm）同拉，
#    缺 -wal 则数据停留在最近 checkpoint；本地先 checkpoint 再校验，
#    之后主文件自洽可单独分发。
#
# ⚠️ run-as 依赖 debuggable 构建：release APK（debuggable=false）无法拉取，
#    开发期统一部署 debug 构建（adb install -r），release 只留给正式发布。
#
# 用法：./tool/backup_db.sh
# 输出：<仓库根>/.backup/contexta-db-<日期>_<时间>/（.backup/ 已被 .gitignore 忽略）
set -euo pipefail

PKG="com.ak.contexta"
DB_DIR="/data/data/$PKG/databases"

# 脚本所在目录（tool/），仓库根 = 上溯 4 层
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
OUT="$ROOT/.backup/contexta-db-$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$OUT"

# 设备连接检查
if ! adb get-state >/dev/null 2>&1; then
  echo "❌ 无设备连接（adb get-state 失败）"
  exit 1
fi

# ── 1. run-as 前置探测（debuggable 检查）──────────────────────────
if ! adb shell run-as "$PKG" ls "$DB_DIR" >/dev/null 2>&1; then
  echo "❌ run-as 不可用：请确认安装的是 debug 构建（release 构建 debuggable=false 无法拉库）"
  exit 1
fi

# ── 2. force-stop：杀掉 UI + 后台 worker，保证没有活跃写者 ────────
echo "⏹  force-stop $PKG ..."
adb shell am force-stop "$PKG"
sleep 1

# ── 3. WAL 三件套一起拉（缺 -wal 则数据停留在最近 checkpoint）─────
# 注意：不用 sh -c 嵌套引号（adb shell 会剥引号导致 test 失效），
# 用 ls 的退出码判断存在性。
for f in contexta.db contexta.db-wal contexta.db-shm; do
  if adb shell run-as "$PKG" ls "$DB_DIR/$f" >/dev/null 2>&1; then
    echo "→ 拉取 $f"
    adb exec-out run-as "$PKG" cat "$DB_DIR/$f" > "$OUT/$f"
  else
    echo "→ 跳过 ${f}（设备端不存在）"
  fi
done

# 主文件必须非空（拉取失败 = 0 字节 = sqlite3 会当成全新空库，integrity 假通过）
if [ ! -s "$OUT/contexta.db" ]; then
  echo "❌ contexta.db 拉取为空（0 字节）：备份中止"
  exit 1
fi

# ── 4. 本地合并：checkpoint 把 WAL 折入主文件 ─────────────────────
sqlite3 "$OUT/contexta.db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || \
  { echo "❌ 本地 checkpoint 失败"; exit 1; }

# ── 5. 三重校验 ───────────────────────────────────────────────────
echo "== 校验 =="
INTEGRITY="$(sqlite3 "$OUT/contexta.db" "PRAGMA integrity_check;" 2>&1 | head -1)"
echo "integrity_check: $INTEGRITY"
[ "$INTEGRITY" = "ok" ] || { echo "❌ 备份损坏"; exit 1; }

USER_VERSION="$(sqlite3 "$OUT/contexta.db" "PRAGMA user_version;")"
echo "user_version: $USER_VERSION"

ARTICLE_COUNT="$(sqlite3 "$OUT/contexta.db" "SELECT COUNT(*) FROM article;")"
DB_VERSION="$(sqlite3 "$OUT/contexta.db" "SELECT version FROM db_version WHERE id = 1;" 2>/dev/null || echo '（无 db_version 表，待 migrate_db.sh 补齐）')"
echo "article 行数: $ARTICLE_COUNT"
echo "db_version: $DB_VERSION"
[ "$ARTICLE_COUNT" -gt 0 ] || { echo "❌ article 行数为 0，备份疑似异常"; exit 1; }

# 与最近一次备份对比行数（粗校验）
LATEST_PREV="$(ls -d "$ROOT/.backup"/contexta-db-* 2>/dev/null | grep -v "$OUT" | sort | tail -1 || true)"
if [ -n "$LATEST_PREV" ] && [ -f "$LATEST_PREV/contexta.db" ]; then
  PREV_COUNT="$(sqlite3 "$LATEST_PREV/contexta.db" "SELECT COUNT(*) FROM article;" 2>/dev/null || echo 0)"
  echo "对比上次备份（${LATEST_PREV}）: $PREV_COUNT → $ARTICLE_COUNT"
fi

echo "✅ 备份完成: $OUT"
