# 词形解析（Inflection Resolution）设计

**日期**：2026-08-11
**状态**：已确认
**来源**：用户报告——文章里点击 "homes"，数据库里有 "home" 词条但精确匹配不到，触发了 LLM 查词

## 背景与问题

查词链路（`WordRepositoryImpl.lookupWord`）是**精确匹配**：

```
点 "homes" → normalize（小写+去首尾标点）→ LRU 缓存 → DB 精确查 spelling_normalized → miss → LLM fallback
```

数据库事实（2026-08-11 核对 asset 库与 wn.db）：

- **不规则词形**（`children`、`went`、`was`、`better`、`men`、`feet`）已经是独立词条，精确匹配可命中 ✅
- **规则词形**（`boxes`、`homes`、`played`、`bigger`）不在库里（oewn `forms` 表只含不规则变化），点它们必然 miss → 触发 LLM ❌

结论：运行时只需解析**规则词形**，不规则形式数据库已覆盖。

## 目标

点击 "homes" 时解析到数据库里的 "home" 词条，避免无谓的 LLM 查词。覆盖三类规则变化：名词复数、动词时态（过去式/过去分词/现在分词）、形容词比较级/最高级。

## 方案：运行时规则型词形解析器（已选）

在 `lookupWord` 的**精确 miss → LLM 之间**插入一层词形解析：

```
点 "homes" → normalize("homes")
 ① LRU 缓存（key=原词 homes）       → 命中直接返回（含标注）
 ② DB 精确匹配                      → 命中返回（不规则词在此命中）
 ③ NEW 词形解析：候选逐一查 DB      → 命中：构建 home 词条 + 附标注，缓存 key=homes
 ④ LLM fallback                    → 不变
```

**未选方案**：

- **Porter 词干提取**：词干 ≠ 词元（`cooking→cook` 误判名词、`has→ha`），需黑名单，不采用
- **前缀模糊匹配**：`homes LIKE 'home%'` 会命中 `homework` 等无关词，不采用
- **ETL 侧扩充词形**：用户明确排除（问题发生在运行时查词）

## 组件设计

### 1. 规则引擎：`InflectionResolver`（纯函数，无 IO）

位置：`lib/domain/inflection/`。输入原词，输出候选列表 `[(lemma, type)]`，按置信度排序。

```dart
enum InflectionType { sForm, pastTense, presentParticiple, comparative, superlative }

class InflectionCandidate {
  final String lemma;
  final InflectionType type;
}

abstract interface class InflectionResolver {
  List<InflectionCandidate> resolveCandidates(String spelling);
}
```

> `sForm` 同时覆盖复数与第三人称单数（`boxes→box`、`plays→play`），二者后缀规则相同、引擎无法区分——**标注文案在仓库层按词元义项词性生成**（见下）。

| 变化类型 | 规则 | 示例 |
|---|---|---|
| 复数 -s | 去 s | homes→home, books→book |
| 复数 -es | 去 es / 去 es + 还原 e | boxes→box, churches→church, caches→cache |
| 复数 -ies | 去 ies 还原 y | cities→city, babies→baby |
| 复数 -ves | 去 ves 还原 f/fe | wives→wife, halves→half |
| 动词 -ed | 去 ed / 去 ed + 双写还原 | played→play, stopped→stop |
| 动词 -ied | 去 ied 还原 y | studied→study, carried→carry |
| 动词 -ing | 去 ing / +e 还原 / 双写还原 | going→go, making→make, running→run |
| 比较级 -er | 去 er / 双写还原 / +e 还原 | larger→large, bigger→big, nicer→nice |
| 最高级 -est | 去 est / 双写还原 / +e 还原 | largest→large, biggest→big, nicest→nice |

拼写还原：双写辅音还原（running→runn→run）、去 e 还原（making→mak→make）、y 还原（cities→citie→city）。每条规则生成多个候选词元，全部查库按序命中第一个。

**实测驱动的规则补全**（正确性实测暴露系统性缺陷后按族补全，与基础规则合并为定稿）：-ie 动词词族（died→die、dying→die，优先于 y 还原）、-ck→-c（panicked→panic）、希腊 -is→-es（analyses→analysis）、拉丁 -ex/-ix→-ices（indices→index）与 -nx→-nges（larynges→larynx）、-ves→-vis（pelves→pelvis）、-nies→-ney（monies→money）、-men→-man 复合词（airmen→airman，守卫见「误判防护」）。候选允许含噪声（如 changes→changx）——由仓储层查库存在性过滤，无害。

**标注文案**：规则引擎只输出粗粒度类型（`sForm`/过去式/现在分词/比较级/最高级），**具体文案在仓库层生成**（`_buildWordDetail` 后已有词条义项词性）：

| 引擎类型 | 词元义项词性 | 文案 |
|---|---|---|
| sForm | 仅名词 | "homes 是 home 的复数形式" |
| sForm | 仅动词 | "plays 是 play 的第三人称单数形式" |
| sForm | 名词+动词都有 | "plays 是 play 的复数形式 / 第三人称单数" |
| pastTense | — | "played 是 play 的过去式/过去分词"（不细分，词典中同词条） |
| presentParticiple | — | "going 是 go 的现在分词" |
| comparative | — | "bigger 是 big 的比较级" |
| superlative | — | "biggest 是 big 的最高级" |

POS 判定用**词性首段精确匹配**：`partOfSpeech.split('.').first` 取首段——`'n.'/'n'` 判名词、`'v.'/'vi.'/'vt.'/'v'` 判动词；`adv.`（含 v）、`pron.`（含 n）、`det./pron.`、`r.`（WordNet 副词）等不以 n/v 开头，不会误判。

### 2. 查词链改造：`WordRepositoryImpl`

- 新增私有方法 `_resolveInflection(normalized)`：调用解析器取候选 → 逐个 `getByNormalized` 查库 → 命中返回 `(WordRow, InflectionType)`
- `lookupWord` 精确 miss 后调用；`findLocal`（手动加词入口 `add_word_usecase`）同样复用，行为一致
- 命中时：`_buildWordDetail` 构建词条 → **按词条义项词性生成标注文案** → `copyWith(inflection: result)` 附标注 → 缓存 key=原词
- 全部候选 miss → 走 LLM（现有逻辑不变）

`WordDetail` 加可选字段 `inflection: InflectionResult?`：

```dart
class InflectionResult {
  final String lemma;          // "home"
  final InflectionType type;   // sForm
  final String note;           // "homes 是 home 的复数形式"（仓库层按词性生成）
}
```

### 3. UI 展示：查词弹窗

```
homes  🔊                    ← 词头：原词（不再替换为 spellingDisplay）
/home/                        ← 音标：词元的
homes 是 home 的复数形式      ← 新增一行小字（muted 色）
─────────────────────────
n. 家；住所                  ← 义项：home 的义项
```

- `WordSheetData` 加 `inflectionNote: String?`
- `ReadingController._lookupWord`：`word` 字段从 `detail.spellingDisplay` 改为原词 `normalized`，标注文案来自 `detail.inflection`
- **加入生词本**：用命中的 `wordId`（home 的 id）——生词本存词元，复习页显示标准词元
- **发音**：读词头原词（`playWordPronunciation` 用 `state.wordSheetData.word`，零改动），符合文章语境

### 4. 误判防护（六层，实测后定稿）

1. **精确匹配先行**——`news`、`bus`、`was` 等库内词直接命中，走不到解析器
2. **候选必须真实存在于 DB**——`has`→`[ha]`，`ha` 不在库 → 不解析
3. **规则词尾例外正则**——`-ss`/`-us`/`-is`/`-as` 结尾不去 s（bus、gas、his、analysis 保护）
4. **入口早退词表 `_sExceptionWords`**（11 个）——本身是词元的例外词不解析：mass noun `news`；单复数同形拉丁借词 `series`/`species`；比较级 er 分支误判源 `her`/`per`（→h/he/p）；`always`；**-man 孪生真词黑名单** `carmen`/`germen`/`somen`/`humen`/`yumen`（其 -man 孪生 german/soman/human/yuman/carman 是库内不同真词，查库滤除失效，只能显式早退）
5. **-men 复合词守卫**——`-men→-man` 要求词长 ≥5 且词干 ≥2 字符（挡 `omen→oman`、`amen→aman`，Oman 国名在库）；`men`/`women` 特例守卫外直接生成
6. **条件例外表**（已启用）——47 条硬编码纯数据映射（拉丁 2 变格 -um→-a、1 变格 -a→-ae、-us→-i、法语 -eau→-eaux、核心不规则复数如 `children→child`、`data→datum`、`cacti→cactus`），实测驱动定稿，无第三方依赖

残余噪声候选（如 `changes→changx`、`speciman`）不在词库，由第 2 层查库滤除——生成保守 + 查库把关，双保险。

## 正确性验证（实测结论）

手写规则的正确性用数据实测，不靠拍脑袋（`test/domain/inflection/accuracy_probe_test.dart`）：

1. **语料**：stardict.db 的 `exchange` 字段（变形标注，如 `homes` 行 `1:s3/0:home`）抽取 `(词形, 词元)` 对——仅测试期使用，不引入运行时依赖；过滤规则：全字母词、排除小写后以 ss/us/is/as 结尾的条目（库内均为地名/人名噪声，如 aaliis→aalii）
2. **指标**：还原率 = 解析器候选命中（lemma 与 type 均匹配）对数 / 总对数
3. **阈值**：≥95% → 规则表定稿；<95% 或发现系统性缺陷 → 补规则与硬编码例外表

**实测过程**：初跑 **83.4%** → 9 处规则补全（-ie 词族、希腊 -is→-es、拉丁 -ex/-ix→-ices、-nx→-nges、-ves→-vis、-nies→-ney、-men→-man、-ck→-c、双写还原）+ 47 条例外表 + 早退词表（定稿 11 个）→ 达标定稿。

**exchange 编码勘误**：实测确认 stardict `exchange` 变形码为 `s/3`=sForm、`p/d`=过去式、`i`=现在分词、`r`=比较级、`t`=最高级（`larger|0:large/1:r`、`biggest|0:big/1:t`）；设计初稿的 `j`=比较级全库 0 次出现、`r`=最高级与实际相反，已按实测修正。

**最终实测**：还原率 **99.4%**（语料 134,764 对，miss 838）。miss 构成：pastTense 556（`ate→eat`、`arose→arise` 等不规则动词——库内独立词条，精确命中先行覆盖，无害）、sForm 255（`Agneaux`、`bassi` 等生僻外来复数）、presentParticiple 26、superlative 1（`furthest→far`）。

**正确性结论**：

| 场景 | 正确性 | 原因 |
|---|---|---|
| 规则变化还原（homes→home 等） | 99.4% | 表驱动规则 + 例外表全覆盖 |
| 不规则词（children、went、better） | 100% | 库内独立词条，精确命中先行，到不了解析器 |
| 残余误判（库外词过度还原） | <1% | 六层防误判压制 |

## 错误处理

- 解析器纯函数无 IO 不 throw（空串/超长词返回空候选）
- 所有候选 miss → 走 LLM（现有 fallback 与降级 UI 不变）
- LLM 失败 → 现有"仅词头"降级逻辑不变

## 测试

**单元测试** `test/inflection_resolver_test.dart`（表驱动）：
- 正向：homes→home、boxes→box、cities→city、wives→wife、played→play、stopped→stop、studied→study、going→go、making→make、running→run、crying→cry、bigger→big、happier→happy、nicest→nice
- 反例：news、bus、has、was、series、gas、his、is（不生成候选或不命中）

**仓库层测试**：解析命中 → LLM 不触发 + 标注正确 + LRU 缓存生效；全部 miss → 正常走 LLM。
**标注文案测试**（词性区分）：词元仅名词义项 → "复数形式"；仅动词义项 → "第三人称单数形式"；两者都有 → "复数形式 / 第三人称单数"。

## 文档同步

完成后按 CLAUDE.md 流程：分析 git diff，同步受影响主题文档（查词链路相关：`database-schema.md` 或新增查词主题文档，提交时判定）。

## 无变更清单

- ETL / 数据库结构 / assets/contexta.db：不变（无迁移）
- LLM fallback 链路：不变
- 生词本 / 复习页数据：不变（存词元 id）
