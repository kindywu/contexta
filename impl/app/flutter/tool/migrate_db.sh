#!/usr/bin/env bash
#
# 数据库版本管理工具（生产脚本，不含 dev 补丁）
#
# 版本模型（与 lib/data/local/tables/settings_tables.dart DbVersion 注释一致）：
#   tool/db_version 文件  = 生产环境已发布版本（0 = 从未发布）
#   db_version 表（库内单例行 id=1）= 已应用编号迁移脚本的最高目标版本
#   （无表/行 = 版本 0：尚未跑过任何迁移的库，含空库与 Room 遗留库）
#   硬校验不变量：库内 version ≤ 文件值 + 1（库超前于发布声明即报错）
#
# 编号脚本链（tool/migrations/NNN-*.sql，NNN = 脚本升级到的目标版本）：
#   001-init.sql（0→1：v1 标准结构）→ 002（1→2）→ 003（2→3）→ …
#   链条完整：未来发布 v5 时遇到 v3 用户库，按序应用 004、005；
#   遇到版本 0 的库（无 db_version 表/行），从 001 起跑完整 init。
#
# 职责：
#   1. 前置校验：integrity_check + 版本硬校验
#   2. 编号迁移段：按序应用 (CUR, TARGET] 区间内的脚本（TARGET = 文件值 + 1，
#      允许开发库比生产领先一个版本）；每个待升级库先存 .bak-v$CUR 保留现场
#
# ⚠️ 开发期（tool/db_version = 0）v1 的结构变更**不写编号脚本**（并入 v1，
#   同步更新 001-init.sql 的 v1 定义）；对已存在 v1 库的补结构用临时补丁脚本
#   （/tmp，不提交仓库），仅用于保留测试数据。
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

# 当前库版本：无 db_version 表/行 = 版本 0（从 001 起跑 init；空库、Room
# 遗留库均落于此）；有表有行 = 已应用编号脚本的最高目标版本
CUR=""
if sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='db_version';" | grep -q db_version; then
  CUR="$(sqlite3 "$DB" "SELECT version FROM db_version WHERE id = 1;" 2>/dev/null || true)"
fi
if [ -z "$CUR" ]; then
  CUR=0
  echo "ℹ️  库内版本: 0（无 db_version 表/行，将从 001-init.sql 开始）"
else
  echo "ℹ️  库内版本: ${CUR}"
fi

# 版本硬校验：库内行 ≤ 文件值 + 1
MAX_ALLOWED=$((PROD_VERSION + 1))
if [ "$CUR" -gt "$MAX_ALLOWED" ]; then
  echo "❌ 库内版本 $CUR > 文件值+1（${MAX_ALLOWED}）：库超前于发布声明，中止"
  exit 1
fi

# ── 编号迁移脚本段：按序应用 (CUR, TARGET] ────────────────────────
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
      cp "$DB" "$DB.bak-v${CUR}"  # 保留现场，失败可恢复
      sqlite3 -bail "$DB" < "$script" \
        || { echo "❌ 脚本失败（现场保留于 $DB.bak-v${CUR}，恢复: mv $DB.bak-v${CUR} ${DB}）"; exit 1; }
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
