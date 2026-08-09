# 编号迁移脚本目录（发布后使用）

本目录存放**生产环境数据库迁移脚本**（1→2→3 的升级），由 `tool/migrate_db.sh`
按序应用。**开发期（`tool/db_version` = 0，未发布）不写本目录脚本**——结构变更
用临时补丁脚本（/tmp 或 temp_docs/，不提交仓库）对真机备份库就地升级。

## 命名与版本约定

- `NNN-描述.sql`，**NNN = 脚本升级到的目标 db_version 值**（把库内版本从
  NNN-1 升到 NNN）。从 **002** 起编号——001 不存在：v1（0→1）是 init 阶段，
  由 drift `createAll`（`lib/data/local/database.g.dart`）与 asset 预置库承载，
  不写编号脚本。
- 同一版本可有多个文件（按文件名升序依次执行），最后一份必须携带
  `UPDATE db_version` 收尾；每个版本整体视为一次迁移。
- NNN 必须与 drift `MigrationStrategy.onUpgrade(from, to)` 的 `to`、
  `schema_migration_log.to_version` 三者一一对应。

## 脚本契约（每条脚本必须满足）

单文件自包含事务，任何一步失败整体回滚：

```sql
BEGIN IMMEDIATE;
-- ... DDL/DML（CREATE TABLE / ALTER TABLE / 数据回填）...
INSERT INTO schema_migration_log (from_version, to_version, description, created_at)
  VALUES (1, 2, 'migrations/002-xxx.sql', '<ISO 时间>');
UPDATE db_version SET version = 2, updated_at = <Unix millis> WHERE id = 1;
COMMIT;
```

- **发布后的新列**：SQLite 的 `ALTER TABLE ADD COLUMN` 不接受「NOT NULL 且无
  DEFAULT」的列——要么 `NOT NULL DEFAULT ...`，要么 nullable 后回填数据。
  与 Room 遗留表「无 DEFAULT」规则不同，发布后的新列规则优先于此。
- `sqlite3` CLI 默认 `foreign_keys = OFF`：脚本内建表顺序不受 FK 约束，但
  「先删子表再删父表」不会报错——靠人工纪律，与 drift onUpgrade 一致。
- 双写纪律：同一变更需同时维护 SQL 脚本（本目录）与 drift onUpgrade 镜像
  （`lib/data/local/database.dart`），脚本头注释里互引文件名
  （`-- 与 lib/data/local/database.dart onUpgrade 002 镜像同步`），
  先写脚本、跑通、再镜像。

## 校验

对目标库执行 `./tool/migrate_db.sh --check <db路径>`：报告 db_version 行、
待应用脚本清单、硬校验（库内行 ≤ 文件值+1）。
