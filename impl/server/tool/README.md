# tool/import-data.ts — 数据导入脚本（pipelin → 服务端业务库）

一次性导入：把文章管线库 `/Users/kindy/Documents/article-pipeline/data/pipeline.sqlite`（旧结构，`articles` 含 `embedding` 列）整体导入服务端业务库（`impl/server/data/contexta.db`），并保留历史文章（全部标为 `approved`）。

## 用法

```bash
cd impl/server
bun run tool/import-data.ts -- --source <pipeline.sqlite> --target <contexta.db> [--backup <dir>]
```

- `--source` — 管线库，**只读**，绝不修改
- `--target` — 服务端业务库；已存在则先备份再整体覆盖
- `--backup` — 备份目录，缺省 = `<target 同目录>/.backup`（即 `data/.backup`）
- 成功：打印 `ImportReport`（JSON）退出 0；任一校验失败：stderr 报错退出 1

## 执行流程（对应设计文档 §5.4）

1. **备份先行**：`mkdir -p backupDir`；`cp source → backupDir/pipeline-source-<YYYYMMDD-HHMMSS>.sqlite`，源旁的 `-wal`/`-shm` 侧车一并拷贝（同后缀）；target 已存在 → `cp target → backupDir/target-<ts>.sqlite`（含侧车）。**源文件只读不动。**
2. **拷贝**：`cp source → target`（**不拷 WAL 侧车**——源主文件已完整；target 旁残留的是旧 target 的侧车，打开时会被 SQLite 判为不匹配而丢弃，不会把旧帧并进新副本）。
3. **去 embedding 重建**：打开 target → `PRAGMA wal_checkpoint(TRUNCATE)`（清理残留侧车）→ 单事务 `CREATE articles_new`（无 embedding）→ `INSERT ... SELECT`（显式列名，含 `thread_id`/`created_at`）→ `DROP articles` → `RENAME`。外键未强制（`foreign_keys=0`），无约束问题；旧的 `idx_articles_*` 索引随 DROP 消失，由下一步重建。
4. **建表**：`ensureSchema(db)`（引擎 4 表 + 索引重建）+ `ensureServerSchema(db)`（服务端表：users、article_review 等）。
5. **历史审核行**：`INSERT OR IGNORE INTO article_review (article_id, slot_id, status, reviewed_by) SELECT s.article_id, s.id, 'approved', 'import' FROM batch_slots s WHERE s.status='success' AND s.article_id IS NOT NULL`（`article_id` UNIQUE，重复导入幂等）。
6. **校验**（任一失败抛错、exit 1）：

   | 校验项 | 规则 |
   |--------|------|
   | 批次数 | `article_batches` 行数 > 0 |
   | 行数保留 | 重建后 `articles` 行数 = 重建前快照（重建不丢行） |
   | 段落一致性 | 每篇 `articles.paragraph_count` = 实际段落数（LEFT JOIN GROUP BY count 对比，全量） |
   | review 行数 | = `articles` 行数 = success 槽位数（本脚本写出的 approved 数） |
   | 完整性 | `PRAGMA integrity_check` = `ok` |

## 输出报告

```json
{ "batches": 8, "articles": 116, "reviewRows": 116, "nonSuccessSlots": 4, "integrity": "ok" }
```

真实导入的期望值：批次 8 / 文章 116 / review 116 / 非 success 槽 4 / integrity ok（批次日历 2026-08-27..09-03）。

## 备份纪律

- **备份永远先于任何写入**；`pipeline-source-*` 与 `target-*` 均携带 `-wal`/`-shm` 侧车——旧 target 的最后写入可能只在侧车里，只拷主文件会丢数据。
- 恢复：`cp` 备份主文件回原路径，并覆盖同名 `-wal`/`-shm`（完整三件套），或先用 `wal_checkpoint(TRUNCATE)` 折入主文件再只拷主文件。
- 每次运行都会先备份再整体覆盖 target，**可重复运行**（上次失败残留的 target 会被本次整体替换）。
- Rust 遗留 `impl/server/contexta.db` 按 §5.4 先在真实导入前 `cp` 到 `.backup/contexta-old-<日期>/` 再弃用（不做删除，留档）——由主会话在真实导入时执行。

## 执行权限

本脚本**不自动执行真实导入**。真实导入（`--source pipeline.sqlite --target impl/server/data/contexta.db`）由主会话经用户确认后另行运行；源库与备份文件不动，导入前先核对报告期望值。
