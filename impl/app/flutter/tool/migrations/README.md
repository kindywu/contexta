# 编号迁移脚本目录（版本链条）

本目录存放**生产环境数据库迁移脚本**（0→1→2→3 的完整版本链条），由
`tool/migrate_db.sh` 按序应用。

## 命名与版本约定

- `NNN-描述.sql`，**NNN = 脚本升级到的目标 db_version 值**（把库内版本从
  NNN-1 升到 NNN）。**从 001 起编号**：
  - `001-init.sql`（0→1）= **版本链条起点**，描述 **v1 标准结构**（17 张表 +
    索引）。全部 `CREATE ... IF NOT EXISTS` 幂等——对空库（全新 init）、
    Room 遗留库（已有 15 张业务表，IF NOT EXISTS 跳过）、任意已有库
    重复执行均安全。
  - `002`（1→2）、`003`（2→3）、……：发布后的结构升级。
  - **链条完整**：未来发布 v5 遇到 v3 用户库，`migrate_db.sh` 按序应用
    004、005；遇到无 db_version 表/行的库（版本 0），从 001 起跑完整 init。
- **001-init.sql 生命周期**：开发期（`tool/db_version` = 0）v1 结构变更时
  **同步更新本文件**（001 描述的 v1 = 当前开发结构）；首次发布 v1（文件改 1）
  后**冻结**，之后的结构变更写 002 起，不得再改 001。
- 同一版本可有多个文件（按文件名升序依次执行），最后一份必须携带
  `UPDATE db_version` 收尾；每个版本整体视为一次迁移。
- NNN 必须与 drift `MigrationStrategy.onUpgrade(from, to)` 的 `to`、
  `schema_migration_log.to_version` 三者一一对应（发布后双写纪律）。

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

（001 的 from_version 为 0，见 001-init.sql 收尾段。）

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
