# CLAUDE.md

本文件为 Claude Code（claude.ai/code）在本仓库工作时提供指引。

## 项目简介

**Contexta（语境）** — 通过"文章→句子→单词"的语境化学习路径，帮助中国用户在阅读真实英文文章的过程中自然习得词汇，告别脱离语境的死记硬背。

产品宣言（飞书文档 · ID: `MJ2EdrtXeojV1mxMBKBcRFtJnvd`）：
[https://mcn65qzhfvdh.feishu.cn/wiki/VLOxw0Pamipz08kFt9Bc7PXbnbf](https://mcn65qzhfvdh.feishu.cn/wiki/VLOxw0Pamipz08kFt9Bc7PXbnbf)

> 可通过 `lark-cli docs +fetch --doc "VLOxw0Pamipz08kFt9Bc7PXbnbf"` 读取文档内容。

产品需求说明书（PRD）（飞书文档 · ID: `MJtudgYqHoxovxxzOyacjN0snvc`）：
[https://mcn65qzhfvdh.feishu.cn/wiki/DmGPw3qsDixoffkUeBTcaw5Anqb](https://mcn65qzhfvdh.feishu.cn/wiki/DmGPw3qsDixoffkUeBTcaw5Anqb)

> 可通过 `lark-cli docs +fetch --doc "DmGPw3qsDixoffkUeBTcaw5Anqb"` 读取文档内容。

系统设计文档（飞书文档 · ID: `SyjkdQliZoVuQOxWuXdchhxTnpe`）：
[https://mcn65qzhfvdh.feishu.cn/docx/SyjkdQliZoVuQOxWuXdchhxTnpe](https://mcn65qzhfvdh.feishu.cn/docx/SyjkdQliZoVuQOxWuXdchhxTnpe)

> 可通过 `lark-cli docs +fetch --doc "SyjkdQliZoVuQOxWuXdchhxTnpe"` 读取文档内容。

## 仓库结构

```
/                   # 根目录 = 文档
  README.md         # 产品概述
  CLAUDE.md         # 本文件
  impl/             # 实现代码（由 AI 根据文档生成）
  impl/app/flutter  # Contexta 的 Flutter 实现
```

### 实现代码中的文档目录

```
impl/app/flutter/docs/                 # 主题文档（按主题描述系统设计，供人类理解系统；当前尚未创建）
impl/app/flutter/temp_docs/            # 临时计划文档（执行复杂任务前编写的计划，执行完后可删除；当前尚未创建）
```

### 文档布局（根目录 `/`）
文档存储在根目录，按类别组织：
- **产品** — 产品需求文档、用户故事
- **原型** — 原型图、线框图、交互稿
- **设计** — 架构设计、数据库设计、API 设计
- **技术约束** — 技术选型、约束条件、权衡决策

### 实现代码（`impl/`）
所有源代码位于 `impl/` 下。代码主要由 AI 根据根目录的文档生成。当前技术栈：Flutter（Dart），本地数据库用 drift（SQLite），状态管理用 flutter_riverpod。

## 入门

项目已有 Flutter 实现（`impl/app/flutter/`），开发在现有代码基础上按"理解 → 实现 → 验证 → 同步文档 → 提交"推进。

## 核心原则

- **语境优先**：通过阅读真实文章习得词汇，而非孤立记忆
- **文档驱动开发**：根目录的文档定义 `impl/` 要构建的内容
- **AI 生成代码**：实现主要由 AI 基于文档生成

## 开发指南

### 工作流程

```
理解（代码+主题文档）→ 实现（代码+测试）→ 验证 → 同步主题文档 → 提交
```

1. **理解**：阅读相关代码和对应的主题文档
2. **实现**：编写/修改代码，编写测试
3. **验证**：确认测试通过
4. **同步**：提交前 AI 分析 git diff，同步所有受影响的主题文档
5. **提交**：代码和文档一同提交

### 主题文档

代码是系统真实完整的知识，文档的主要作用是帮助人理解系统。因此文档按主题组织：

- 每个主题独立成文（如：架构分层、依赖注入、文章生成管道、查词系统……），放在 `docs/` 下
- 记录当前设计和决策理由，不记录历史迭代（git log 已承载变更历史）
- 方案变迁（A → B → C → D）最终只记录 D，不记录中间过程
- 变更时 AI 识别所有受影响的主题文档，一次性同步更新
- 主题可以新增、合并、拆分、废弃

**主题文档质量要求（写每个主题时都必须满足）**：

1. **内容完整**：覆盖该主题的实现全貌——参与角色、调用链、状态机、数据形态、错误处理。目标是：人类不读代码也能理解系统如何运转
2. **多角度描述**：同一主题从多个侧面展开（业务功能线、技术实现线、数据模型线、错误处理线……），每个角度独立成节，互不混写
3. **UML 精确描述**：动态行为用 UML 状态图 / 时序图 / 活动图，静态结构用 UML 类图 / ER 图（Markdown 中用 Mermaid 编写，` ```mermaid ` 代码块）。图表达精确关系，文字只作图的补充说明

### 文档同步规则

1. **同步时机**：代码编写、测试通过后、提交前，AI 分析本次 git diff
2. **同步范围**：识别所有受影响的主题文档，更新对应章节
3. **临时文档**：`temp_docs/` 中的计划文档执行完即删

## 数据库设计规则

### 规则总览

| 规则 | 说明 | 设计时引用 |
|------|------|-----------|
| NF | 三大范式校验，违反须记录决策 | `db:NF` |
| REL | 实体间关系声明 | `db:REL` |
| TYPE | 区分长期实体 / 流水账 / 关系 | `db:TYPE` |
| PK | 主键策略 | `db:PK` |
| NAME | 命名规范 | `db:NAME` |
| INDEX | 索引策略 | `db:INDEX` |
| INTEGRITY | 数据完整性约束 | `db:INTEGRITY` |
| MIGRATION | 数据库迁移策略 | `db:MIGRATION` |

---

### NF — 三大范式

**规则**：设计实体时按三大范式校验，若违反需在实体注释或主题文档中记录决策理由。

1. **1NF（原子性）**：每一列不可再分，不存 JSON 字符串或序列化对象
   - ✅ `article.title: String`
   - ❌ `article.tags: String`（存 "tech,science,news"）

   例外：明确需要字段灵活性且查询不依赖拆分内容时，使用 Dart 序列化（`jsonEncode` / `jsonDecode` 存 TEXT）并加注释说明原因。

2. **2NF（完全依赖）**：非主键列必须完全依赖于全部主键（消除部分依赖），主要针对联合主键
   - 联合主键的表中，所有非主键列需描述"整条记录"，而非仅描述某个主键代表的实体

3. **3NF（传递依赖）**：非主键列不传递依赖于主键（消除传递依赖）
   - 实体 A 的列不应包含实体 B 的列，除非是外键

**违反时必须记录的决策理由类型**：
- **性能**：反范式化减少 JOIN，如将 `user_name` 冗余到 `order` 表
- **复杂度**：降低实现难度，如用 JSON 字段存灵活配置
- **外部约束**：API 返回格式、第三方数据模型

> 示例：`daily_learning` 表包含 `batch_difficulty` 字段（冗余 Batch 的难度），违反 3NF。理由：首页按难度筛选学习记录时避免 JOIN，提升查询性能。—— `db:NF`

---

### REL — 实体间关系

**规则**：实体间的关系必须声明类型，并在建表和查询时遵循对应模式。

| 关系类型 | 实现方式 | 适用场景 |
|---------|---------|---------|
| **1:1**（一对一） | 外键 + UNIQUE，或共享主键 | 用户 ↔ 用户设置 |
| **1:N**（一对多） | 外键在「多」方 | 批次 ↔ 文章 |
| **M:N**（多对多） | 中间关联表（含关系属性） | 单词 ↔ 例句 |
| **Parent-Child**（父子/树形） | `parent_id` 自引用外键 | 分类树、评论嵌套 |
| **DAG**（有向无环图） | 关联表 + 闭包表（closure table）| 前置依赖、学习路径 |

**设计时需说明**：关系类型、外键字段、级联策略（CASCADE / SET NULL / RESTRICT）。

> 示例：`Article → Paragraph` 是 1:N，外键 `article_id` 在 `article_paragraph` 表，`ON DELETE CASCADE`。—— `db:REL`

---

### TYPE — 实体类型划分

**规则**：每个实体必须声明属于以下三种类型之一，类型决定了必备字段和行为。

#### 📦 长期实体（Long-lived Entity）

描述业务核心对象，生命周期长，会反复读取和修改。

| 必备字段 | 类型 | 说明 |
|---------|------|------|
| `created_at` | `Long` | 创建时间（Unix millis） |
| `updated_at` | `Long` | 最后更新时间 |
| `is_deleted` | `Boolean` | 软删除标记，默认 `false` |
| `deleted_at` | `Long?` | 删除时间，仅 `is_deleted = true` 时有值 |

查询默认加 `WHERE is_deleted = 0`，除非刻意查已删除数据。

> 你的项目：`Article`, `ArticleBatch`, `Word`, `UserSettings` 都是长期实体。—— `db:TYPE`

#### 📋 流水账（Journal / Log / Snapshot）

记录某个时间点发生的事件或快照，写入后极少修改，通常以追加为主。

| 必备字段 | 类型 | 说明 |
|---------|------|------|
| `created_at` | `Long` | 记录时间 |
| **快照字段** | 视情况 | 记录当时的上下文（配置值、价格、状态），而不是引用当前值 |

**为什么需要快照字段**：流水账的时间敏感性——如果只引用当前配置，历史记录会随配置变更而失真。例如订单存 `product_price` 而非引用 Product 表当前价格。

> 你的项目：`DailyLearningLog`, `GenerationPipelineStatus` 是流水账。—— `db:TYPE`

#### 🔗 关系实体（Relationship）

描述两个或多个实体之间的关联，可带时间范围和属性。

| 必备字段 | 类型 | 说明 |
|---------|------|------|
| `relation_start_at` | `Long?` | 关系开始时间 |
| `relation_end_at` | `Long?` | 关系结束时间（`null` 表示当前有效） |
| 关系属性 | 视情况 | 描述这个关系的特征（如：顺序、权重、角色） |

**时间范围**使关系可追溯——过去有效但现已失效的关系不会丢失。

> 你的项目：`VocabularyEntry`（用户 ↔ 生词 + 掌握状态）是关系实体。—— `db:TYPE`

---

### PK — 主键策略

**规则**：主键类型根据实体类型选择。

| 实体类型 | 推荐主键 | 说明 |
|---------|---------|------|
| 长期实体 | `Long` 自增（drift `integer().autoIncrement()()`） | 简单、高效 |
| 流水账 | `Long` 自增 | 追加写入，自然递增 |
| 关系实体 | `Long` 自增 或 联合主键 | 联合主键防重复 |
| 映射/字典表 | 业务主键（如枚举名、代码） | 可读性优先 |
| 需外部引用的 | `UUID` / `String` | 避免暴露自增 ID |

drift 中联合主键（或无自增主键）通过 `Set<Column> get primaryKey => {...}` 覆盖声明。

> 你的项目：`DailyLearning` 表用 `learning_date`（ISO 日期，TEXT）作为主键（`Set<Column> get primaryKey => {learningDate}`），确保每天最多一条学习记录。—— `db:PK`

---

### NAME — 命名规范

| 元素 | 规范 | 示例 |
|------|------|------|
| 表名（drift Table） | 落库名小写蛇形、单数（复数类名 + `tableName` 显式覆盖） | `class ArticleBatches` → `article_batch` |
| 字段名 | 小写蛇形 | `created_at`, `is_deleted` |
| 关联外键 | `父表名_id` | `batch_id`, `article_id` |
| 布尔字段 | `is_xxx` / `has_xxx` | `is_deleted`, `is_read` |
| DAO | 单数 + `Dao` | `ArticleDao`, `WordDao` |
| 数据类（drift Row） | 单数 + `Row`（`@DataClassName`） | `ArticleRow`, `ArticleBatchRow` |

---

### INDEX — 索引策略

**规则**：仅为查询频次高的字段建索引，不预先建所有可能用到的索引（写放大）。

| 场景 | 索引类型 | 示例 |
|------|---------|------|
| 外键 | 单列索引 | `batch_id` |
| 频繁 WHERE 筛选 | 单列索引 | `is_deleted`, `status` |
| 频繁排序/分组 | 单列索引 | `created_at`, `display_order` |
| 多条件组合查询 | 联合索引（最左前缀原则） | `(status, created_at)` |

联合索引遵守**最左前缀原则**：`(a, b, c)` 索引覆盖 `WHERE a=?`, `WHERE a=? AND b=?`, `WHERE a=? AND b=? AND c=?`，但不覆盖 `WHERE b=?`。

---

### INTEGRITY — 数据完整性

**规则**：尽量在数据库层面保证数据完整性，不依赖应用层。

1. **NOT NULL**：业务上必有值的字段必须声明 `NOT NULL`
2. **DEFAULT**：有合理默认值的字段设置 DEFAULT
3. **外键**：drift 支持外键（`customConstraint` 声明 `FOREIGN KEY`），但当前项目未启用——原因是非破坏性迁移的成本较高
4. **UNIQUE**：联合唯一或单字段唯一用 `@TableIndex(unique: true)`

---

### MIGRATION — 迁移策略

**版本模型**：`tool/db_version` 文件 = 生产已发布版本（`0` = 从未发布生产环境）；库内 `db_version` 表（单例行 `id=1`）= 已应用编号脚本的最高目标版本（**无表/行 = 版本 0**：尚未跑过任何迁移的库，含空库与 Room 遗留库）。硬校验不变量：**库内 version ≤ 文件值 + 1**（库领先发布声明 → 报错）。`db_version`（当前版本指针）与 `schema_migration_log`（迁移历史账本）职责分离，互不推导。

| 阶段 | 策略 |
|------|------|
| 0→1（未发布，`tool/db_version` = 0） | **`tool/migrations/001-init.sql` 提交仓库**——版本链条起点（0→1 init），描述 v1 标准结构，全部 `IF NOT EXISTS` 幂等（空库 / Room 遗留库 / 任意已有库重复执行均安全）。开发期 v1 结构变更**并入 v1 不递增**，**同步更新 001**（001 描述的 v1 = 当前开发结构）；对备份库 / 真机旧库的补结构用**临时补丁脚本（放 `/tmp`，不提交仓库）**，用完即弃。**首次发布 v1（文件改 1）后 001 冻结**，之后的结构变更写 002 起 |
| 1→2→3（发布后，`tool/db_version` ≥ 1） | 每次 schema 变更**递增版本**，写编号迁移脚本**并提交**：`tool/migrations/NNN-*.sql`（NNN = 目标版本：001 = init（0→1），发布后从 002 起），单文件自包含事务，`INSERT INTO schema_migration_log` + `UPDATE db_version` 收尾；drift `MigrationStrategy.onUpgrade` 在发布后**镜像同一批变更**（双写纪律，脚本与 onUpgrade 互引注释）。**链条完整**：未来发布 v5 遇到 v3 用户库，`migrate_db.sh` 按序应用 004、005 |
| 大版本 | 渐进式迁移，一次升一个版本 |

**发布后新列规则**：SQLite `ALTER TABLE ADD COLUMN` 不接受 `NOT NULL` 且无 DEFAULT 的列——发布后新增列用 `withDefault()` 或 nullable + 回填，否则上线会失败。

**sqlite3 CLI 纪律**：CLI 连接默认 `foreign_keys=OFF`，只用于只读校验 / 纯 DDL 补丁；业务读写一律走应用（drift）。

**tool/ 目录纪律**：`tool/` 只放生产脚本与升级脚本（`db_version` 文件、`migrate_db.sh`、`backup_db.sh`、`migrations/`）。**dev 补丁脚本不进仓库**，只在备份升级结构时临时使用。

> 命令：`./tool/backup_db.sh`（备份真机库）→ `./tool/migrate_db.sh <db路径> [--check]`（就地升级）——详见 [docs/database-schema.md](impl/app/flutter/docs/database-schema.md)。

---

## 数据库与部署纪律（防卸载 / 防丢数据硬闸）

**背景**：2026-08-09 曾因 `flutter install` 签名不匹配触发自动卸载，清空设备数据库。以下规则为硬闸，任何情况不得绕过。

### 部署纪律（严禁卸载）

1. **绝不使用 `flutter install` / `flutter run` 覆盖真机**——二者签名不匹配（release↔debug）时都会**静默卸载**旧包。只允许 `adb install -r`（失败会报错，不会卸载）。`flutter run` 只用于模拟器。
2. **部署前核对签名**：`apksigner verify --print-certs app-debug.apk | grep SHA-256` vs `adb shell dumpsys package com.ak.contexta | grep signatures`（小写去冒号比对）；设备无包则跳过。
3. **部署前核对 versionCode**：`dumpsys` 的 versionCode 大于 APK 则中止（**降级同样触发卸载路径**）。
4. **卸载设备 app 前，必须先备份**：`tool/backup_db.sh` → `tool/migrate_db.sh <备份副本> --check` 确认可升级 → 再卸载。
5. **run-as 依赖 debuggable 构建**：release 构建（debuggable=false）无法 run-as 拉库。开发期统一部署 debug APK（`adb install -r`），release 只留给正式发布。

### 数据库结构变更流程（保留数据）

1. **备份先行**（永远第一步）：`tool/backup_db.sh`（WAL 三件套齐拉：contexta.db + -wal + -shm）。
2. `tool/migrate_db.sh <备份副本> --check` → 实跑 → 校验 `SELECT version FROM db_version`。
3. **推回设备**：force-stop → push 副本到 `/data/local/tmp` → chmod 666 → run-as **先删设备端 -wal/-shm 再** cp 主文件（残留 WAL 帧会污染新库）→ 拉回验证（integrity / 表数 / 行数）。
4. 部署新 APK：签名核对 → versionCode 核对 → `adb install -r` → `adb shell monkey -p com.ak.contexta 1` 启动验证。

### Asset 库刷新纪律

**`assets/contexta.db` 与真机库同构，结构变更时必须同步刷新**：

1. 副本 `PRAGMA wal_checkpoint(TRUNCATE)`（把 WAL 折入主文件）；
2. cp 到 `assets/contexta.db`；
3. **`rm -f` 侧车文件**（contexta.db-wal / contexta.db-shm）——git 会漏掉 -wal，残留即静默丢数据；
4. 校验：17 张表（+ Room 遗留表）、db_version 行 = 1、user_version = 1、article 行数 > 0、integrity_check = ok。

> ⚠️ asset 库携带个人数据（真机库拷贝），当前单人应用接受；将来对外分发需先脱敏。

### 备份冷存档

`.backup/`（仓库根，已 gitignore）存放真机备份，**每月做一次冷备份**：`git add -f .backup/contexta-db-*` 提交最近一次备份。任何删除备份的操作必须先确认对象是本次会话产物，**绝不删除既有备份**。
