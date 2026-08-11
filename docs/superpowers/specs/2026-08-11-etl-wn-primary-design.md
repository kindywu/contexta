# ETL 重构设计：wn 为主数据源，stardict 为中文增强

日期：2026-08-11　状态：已批准（方案 A）

## 背景与动机

原 ETL（2026-08-10 设计）以 **stardict（ECDICT）340 万词**驱动词集合，wn 只作被动查询。问题：

1. stardict 词表含大量**短语/垃圾词条**（"a bit of"、"as soon as possible" 等），不是我们想要的单词
2. 阅读场景需要的是真实英文单词的词典数据

目标：**词集合 100% 来自 wn（英文 WordNet）**，stardict 退居「中文释义增强」角色。

## 实测数据（ref/wn.db，2026-08-11）

| 指标 | 数值 |
|---|---|
| wn.db 双 lexicon | oewn:2025+（en，rowid=1）／ omw-cmn:1.4（中文词网，rowid=2） |
| oewn 去重 forms | 157,677 |
| oewn 无空格单词词形 | **≈ 89,899（约 9 万）** |
| 中文词形污染 | omw-cmn 63,341 条中文词形（definitions 0 条、例句 0 条）——必须按 lexicon 过滤 |
| 9 万单词 → stardict 中文命中 | **99.0%** |
| 例句 / IPA 覆盖 | 49,724 条（~30%）／ ~4.4 万（~50%） |
| 全量 JSONL 预估 | 30–50MB；asset 库预估 20–40MB |

### 为什么不用 omw-cmn 当中文源（已评估，否决）

omw-cmn 是 OMW 项目的中文词网：中文词形 → 概念（ILI 对齐），**无任何释义文本**（实测可取到释义比例 0.0%）。抽样对比（run/take/dog/key）：

- 概念级准确但**不是翻译**：无词性分组、同义词冗余（跑/奔跑/跑步/奔）、无语境（take→"租"无"租用（房屋）"说明）、概念标签噪声（dog→"法兰克福香肠"来自 hot dog 义项）
- 覆盖率仅 43.7%，词形变化词更低
- 结论：stardict 的词典级翻译（词性分组、常用义精炼）对 wn 词集质量可靠，保留为唯一中文源

## 方案 A：wn 驱动的对齐重构

保持现有 dump/import 双命令 + JSONL 中间格式架构，改动集中在 3 个文件：

### 1. `src/wn.rs` 新增 `stream_forms()`（词集枚举）

流式游标，模式同 `stardict::stream_all`：

```sql
SELECT DISTINCT form FROM forms
WHERE lexicon_rowid = (SELECT rowid FROM lexicons WHERE id LIKE 'oewn%')
  AND form NOT LIKE '% %'
ORDER BY form
```

- 走 form_index，排序/去重由索引完成
- **lexicon 过滤是硬约束**：否则 6.3 万中文词形（omw-cmn）混入词集
- 空格过滤：阅读 UI 按单词点选，含空格词形（专有名词/复合词/短语动词 6.7 万条）永远查不到，排除
- 现有 `senses/examples/ipa` 三连查不动（按词精确匹配天然隔离中文词形；防御性可加 lexicon 条件）

### 2. `src/dump.rs` 主循环反转 + `build_entry` 重构

- `--all`：从 `stardict::stream_all` 改为 `wn::stream_forms` 驱动；每词 `stardict::lookup_word` 取增强（Option）
- `--words`/sample：不再依赖 stardict 词集——直接对每个词 build_entry，wn 无义项 → 跳过并警告
- `build_entry` 新签名：`(word, sd: Option<&StardictRow>, wn_conn, max_samples)`
  1. wn senses 为空 → **返回 None（跳过）**，删除「stardict 造空义项」兜底分支
  2. wn 义项为主（≤8 条）；stardict 中文按词性块 1:1 映射（现逻辑保留）
  3. stardict 无中文 → 「（无中文释义）」占位（i==0）/ 空串（i>0）
  4. IPA：wn 优先，stardict.phonetic 回退（保留）
  5. 例句：wn 独占、含词过滤、sense 0 标 is_primary（保留）
- `--limit` / `StopLimit` 中断语义保留

### 3. `src/stardict.rs` 删 `stream_all()`

无调用者（词集不再枚举 stardict）。保留 `lookup_word()` 作增强。

### 4. 不改的部分

- `model.rs` JSONL 结构（三表落库契约不变）
- `importer.rs`（保守幂等、每词事务不变）
- `align.rs` 纯函数（parse_cn_blocks / allocate_examples / norm_pos 不变）
- Flutter 侧三表 schema 不动（无来源标记列——词集纯 wn 后无区分需求）

## 错误处理与边界

| 场景 | 行为 |
|---|---|
| wn 无义项的英文词形 | 跳过（eprintln 警告 + 计数）；app 运行时 LLM 兜底覆盖 |
| stardict 查不到中文 | 「（无中文释义）」占位 |
| 目标库已存在词 | dump/import 双层幂等跳过（保留） |
| 大小写重复词形（X-ray/x-ray） | import 幂等兜底（spelling_normalized 小写唯一） |

## 测试

- `wn_test.rs`：新增 stream_forms 断言（~9 万行、全英文无空格、排序、无中文词形）
- `import_test.rs`：dump 2 词 → import → 幂等校验（驱动词改为 wn 词）
- `build_entry` 行为：wn 无义项 → None（实测找一个无义项英文词形）
- 删 `stardict_test.rs` 的 stream_all 断言

## 验证（端到端）

1. `cargo test` 全绿
2. 全量 `cargo run --release -- dump --all` → `impl/etl/tmp/import_words.jsonl`
   - 行数 ≈ 9 万；抽样验证 dog/run/water 词条（义项、中文、例句、IPA）
   - 中文词形 0 条（grep 中文字符验证）
3. `import` 全量导入（本次可选，交付范围 = JSONL 中间文件）

## 文档同步

- 更新 `impl/app/flutter/docs/import_stardict_words.md`（wn 驱动语义、lexicon 过滤、空格排除）——考虑改名 import_words.md
- 本文档为本决策记录（含 omw-cmn 评估）
