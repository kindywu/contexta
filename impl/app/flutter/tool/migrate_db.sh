#!/usr/bin/env bash
#
# 数据库版本管理工具（生产脚本，不含 dev 补丁）
#
# 版本模型（与 lib/data/local/tables/settings_tables.dart DbVersion 注释一致）：
#   tool/db_version 文件  = 生产环境已发布版本（0 = 从未发布）
#   db_version 表（库内单例行 id=1）= 已应用编号迁移脚本的最高目标版本（无脚本则 1）
#   硬校验不变量：库内 version ≤ 文件值 + 1（库超前于发布声明即报错）
#
# 职责：
#   1. 前置校验：integrity_check + 版本硬校验
#   2. 确保段：db_version 表 + 单例行存在（缺表 CREATE、缺行 INSERT version=1）
#      —— 与 app 打开自愈（database_open.dart beforeOpen）相同幂等操作
#   3. 编号迁移段：按序应用 tool/migrations/NNN-*.sql（发布后 1→2→3 使用；
#      db_version=0 未发布阶段无编号脚本，此段空转）
#
# ⚠️ 开发期（db_version=0）的结构变更**不写编号脚本**：用临时补丁脚本
# （/tmp 或 temp_docs/，不提交仓库）对真机备份库就地升级，仅用于保留测试数据。
#
# 用法：
#   ./tool/migrate_db.sh <contexta.db 路径> [--check]
#   （默认实跑；--check 只打印差异，不修改）
set -euo pipefail

DB="${1:?用法: migrate_db.sh <db路径> [--check]}"
CHECK="${2:-}"

# 脚本所在目录（tool/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"

if [ ! -f "$DB" ]; then
  echo "❌ 数据库不存在: $DB"
  exit 1
fi

# 生产版本（文件值；缺失按 0 处理）
PROD_VERSION="$(cat "$SCRIPT_DIR/db_version" 2>/dev/null || echo 0)"
echo "ℹ️  生产版本（tool/db_version）: $PROD_VERSION"

CHANGED=0

# ── 0. 前置校验 ────────────────────────────────────────────────────
INTEGRITY="$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>&1 | head -1)"
if [ "$INTEGRITY" != "ok" ]; then
  echo "❌ integrity_check 失败: $INTEGRITY"
  exit 1
fi

# 当前库版本（db_version 表可能不存在，探测后为空串）
CUR=""
if sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='db_version';" | grep -q db_version; then
  CUR="$(sqlite3 "$DB" "SELECT version FROM db_version WHERE id = 1;" 2>/dev/null || true)"
fi

# ── 1. 确保段：db_version 表 + 单例行（与 app 自愈 SQL 一致）──────
if [ -z "$CUR" ]; then
  echo "🔧 补 db_version 表 + 单例行（version=1）"
  CHANGED=1
  if [ "$CHECK" != "--check" ]; then
    NOW_MS=$(( $(date +%s) * 1000 ))
    sqlite3 "$DB" <<SQL
CREATE TABLE IF NOT EXISTS \`db_version\` (
  \`id\` INTEGER NOT NULL PRIMARY KEY,
  \`version\` INTEGER NOT NULL,
  \`updated_at\` INTEGER NOT NULL
);
INSERT OR IGNORE INTO db_version (id, version, updated_at) VALUES (1, 1, $NOW_MS);
SQL
  fi
  CUR=1
else
  echo "✅ db_version 表已存在（version=${CUR}）"
fi

# 版本硬校验：库内行 ≤ 文件值 + 1
MAX_ALLOWED=$((PROD_VERSION + 1))
if [ "$CUR" -gt "$MAX_ALLOWED" ]; then
  echo "❌ 库内版本 $CUR > 文件值+1（${MAX_ALLOWED}）：库超前于发布声明，中止"
  exit 1
fi

# ── 2. 编号迁移脚本段（发布后使用；未发布则空转）──────────────────
TARGET=$((PROD_VERSION + 1))
PENDING=""
if [ "$CUR" -lt "$TARGET" ]; then
  for n in $(seq $((CUR + 1)) "$TARGET"); do
    for script in "$MIGRATIONS_DIR"/$(printf '%03d' "$n")-*.sql; do
      [ -e "$script" ] && PENDING="$PENDING $script"
    done
  done
fi

if [ -n "$PENDING" ]; then
  echo "🔧 待应用迁移脚本:$PENDING"
  CHANGED=1
  if [ "$CHECK" != "--check" ]; then
    for script in $PENDING; do
      echo "→ 应用 $script"
      cp "$DB" "$DB.bak-v$CUR"  # 保留现场，失败可恢复
      sqlite3 -bail "$DB" < "$script" \
        || { echo "❌ 脚本失败（现场保留于 $DB.bak-v$CUR，恢复: mv $DB.bak-v$CUR ${DB}）"; exit 1; }
      CUR=$((CUR + 1))
    done
  fi
else
  echo "✅ 无待应用迁移脚本"
fi

# ── 收尾 ──────────────────────────────────────────────────────────
if [ "$CHANGED" = "0" ]; then
  echo "✅ 无缺失项，无需升级: $DB"
elif [ "$CHECK" = "--check" ]; then
  echo "🔧 --check 模式：发现差异（未修改）: $DB"
else
  echo "🔧 升级完成: ${DB}（db_version=${CUR}）"
fi
