本目录：

| 文件 | 作用 |
|------|------|
| `import-phonetics-audio.ts` | **App 实际使用的那套**：本地录音包（zip）→ `assets/phonetics/`（音标 48 + 例词 48） |
| `fetch-phonetics-yyb.ts` | 已退役：英语音标网 → App assets（2026-09-21 前的素材源，见文末「退役的抓取链路」） |
| `fetch-phonetics.ts` | 已退役：Cambridge 源抓取（44/48），曾是上一套的补齐素材 |
| `lib/webview.ts` | 上面两个抓取脚本共用的 Bun.WebView 骨架（硬超时守卫、软导航轮询、页面内串行批量下载） |
| `import-data.ts` | 服务端数据导入（pipelin → 服务端业务库） |

---

# tool/import-phonetics-audio.ts — 音标录音导入（录音包 → App assets）

把人工提供的录音包（zip）导入 `assets/phonetics/`。包内两个目录：`音标/` 48 个音标本身 + `例句/` 48 个例词，文件名形如 `01_iː.mp3`、`01_iː_see.mp3`（序号 + 符号 [+ 例词]）。

**为什么换掉抓取链路**：抓来的那套音色不统一（30 个音标网播音员 + 18 个 Cambridge 播音员，站上缺的 18 个文件已删），且**例词只有 TTS 没有录音**。新包是同一播音员的一套，音标与例词都能放录音。详见 [docs/phoneme-audio.md](../../app/flutter/docs/phoneme-audio.md)。

## 用法

```bash
cd impl/server
bun run tool/import-phonetics-audio.ts --zip <录音包.zip> [--out <dir>]
```

| 参数 | 缺省 | 说明 |
|------|------|------|
| `--zip` | **必填** | 录音包路径 |
| `--out` | `impl/app/flutter/assets/phonetics` | 输出目录 |

## 执行流程

1. `ditto -x -k` 解压到临时目录（zip 内是非 ASCII 文件名，`unzip` 会按 CP437 猜错编码；包内可能套一层目录，脚本自动往里找 `音标/`）。
2. 两个目录各按 `<序号>_<符号>[_<例词>].mp3` 解析，按序号配对；只在一侧出现的序号直接报错退出（避免「音标有、例词没有」的半套素材落盘）。
3. 落盘 `s01.mp3`…`s48.mp3`（音标本身）+ `w01.mp3`…`w48.mp3`（例词），并清掉目录里旧的 `v*.mp3` / `c*.mp3`。
4. 写 `manifest.json`：`symbol` / `normalized` / `keyword` / `file` / `wordFile`。
5. 覆盖率比对：从 `lib/ui/reference/reference_data.dart` 的 `phonicsGroups` 正则读出 App 需要的 48 个符号（不在脚本里重复维护清单），缺符号则退出码 1。

## 输出

```
assets/phonetics/
  s01.mp3 … s48.mp3   # 音标本身
  w01.mp3 … w48.mp3   # 例词（序号与音标一一对应）
  manifest.json
```

**为什么落盘不用包内的 IPA 文件名**：macOS 默认大小写不敏感、Unicode 还有 NFC/NFD 归一化差异，manifest 里的名字可能和实际文件名对不上。文件名只当不透明句柄，**符号 → 文件以 manifest 为准**；包内原名不再保留（导入后不复用原包，需要时重新 `--zip` 导一次）。

## 后续（尚未做）

- 版权：录音来源需确认；**对外分发前先确认授权**（与 asset 库携带个人数据同一类约束）。
- 表格例词与录音的一致性靠测试守门（`reference_data_test`）：换包后例词变了，表里没跟着改就直接红。

---

# 退役的抓取链路

> 以下两个脚本是 2026-09-21 前的素材来源，**产物已不再进 App**（见上节新链路）。保留是因为它们记录了那套素材的来路与那些坑（源站死链、限流）；重跑没有意义——App 用的已经是人工录音包。

# tool/fetch-phonetics.ts — 音标发音抓取（Cambridge 源）

抓取 Cambridge Dictionary [Pronunciation symbols](https://dictionary.cambridge.org/us/help/phonetics.html) 页上每个音标的发音 mp3（50 个音标 × UK/US × 音素声/例词声 = 176 个文件）。

**它的产物不直接进 App**：App 用的是 `fetch-phonetics-yyb.ts` 那套（48/48 齐全）。本工具现在的作用是**补齐素材源**——英语音标网那 18 个被站长删掉的录音从这里复制过去（见下一节）。所以输出目录必填且建议放临时目录，别写进仓库。

## 用法

```bash
cd impl/server
# 输出目录必填（本工具产物不随仓库携带），建议放临时目录：
bun run tool/fetch-phonetics.ts --out /tmp/cambridge-phonetics
```

| 参数 | 缺省 | 说明 |
|------|------|------|
| `--out` | **必填** | 输出目录。不设默认值：App 用的是 yyb 那套，默认写进 `assets/phonetics/` 会把 176 个同名不同源的 Cambridge 文件倒进 App 素材目录 |
| `--force` | 否 | 重下已存在的文件；缺省**跳过已存在**（断点续跑：失败重跑只补缺口） |
| `--regions` | `uk,us` | 只取某区域，如 `--regions uk` |
| `--batch` | 6 | 每次 evaluate 取回的 URL 数（批内**串行**，见下） |
| `--delay` | 150 | 批内每个请求之间的间隔（ms） |

## 为什么走 Bun.WebView 而不是 fetch/curl

mp3 在 `dictionary.cambridge.org` 同源路径下，而该站对非浏览器客户端会限流。在**页面上下文里** `fetch` 既带上了浏览器自身的 UA / Cookie / TLS 指纹，又不触发 CORS——本项目抓站的一贯做法（见 `src/engine/sites/common.ts`）。

**限流是实测过的**：并发抓（`Promise.all` 8 个）在百来个请求后开始成片返回 **429**（首轮 176 个里挂了 72 个）；改成**串行 + 退避重试**后 176 个全过（重跑补缺口只发 1 个请求）。429 优先读 `Retry-After`，取不到就指数退避（1s/2s/4s/8s，上限 30s，最多 5 次尝试）。**别再改回并发。**

## 执行流程

1. 软导航到 phonetics 页（`navigate()` 要等广告/统计脚本等全部子资源，慢；改为自行跳转 + 轮询 `table[summary='Vowels'|'Consonants']` 出现）。
2. **页面内**解析两张表（用 DOM 语义而非外层正则 HTML，不依赖属性顺序与空白），得 `{符号, 例词, 音素录音, 例词录音}`；两者各有 UK/US。
3. 页面内串行下载 → base64 → 外层落盘。单个约 25KB，base64 约 33KB，一次 evaluate 传一批安全。
4. 落盘前校验：合法 mp3 必须带 `ID3` 头或以 MPEG 同步字 `0xFF` 开头，且 > 512 字节——拦下「HTTP 200 但内容是拦截页」。
5. 写 `manifest.json`，打印覆盖率报告。

## 输出

沿用 Cambridge 自己的 basename（天然唯一，避免同名例词冲突——`d` 与 `eɪ` 都用 "day"，源站已用 `_001`/`_002` 区分）。**输出目录由 `--out` 指定、不设进仓库的默认位置**（App 用的那 18 个已固化在 `assets/phonetics/` 里，这 176 个文件不必随仓库携带）：

```
<--out 目录>/
  uk_phonetics_sound_sheep_2023feb.mp3   # 音素本身（UK）
  uk_phonetics_word_sheep_2023feb.mp3    # 例词 sheep（UK）
  us_...mp3                              # 同上 US
  manifest.json
```

`manifest.json`：`symbol`（IPA）→ `keyword`（例词）→ 各区域 `sound` / `word` 文件名。App 按符号取用，不必硬编码文件名。

## 覆盖率：44 / 48

App 需求清单**不在本脚本里重复维护**，而是从 `lib/ui/reference/reference_data.dart` 的 `phonicsGroups` 正则读出（避免两处清单漂移），与抓到的符号比对后报告。

恒定的 4 个缺口：**`/tr/ /dr/ /ts/ /dz/`**。它们不是 IPA 音素，而是中国教材单列的音丛，Cambridge 页面没有独立录音。**这 4 个由 `fetch-phonetics-yyb.ts`（见下）那套补齐**；本工具的产物只作补齐素材，不进仓库。

Cambridge 另有 6 个 App 未用：`ɝː` `ɚ` `oʊ` `aɪə` `aʊə` `t̬`（美式变体与卷舌音）。符号比对时 `ɡ`(U+0261，App 用) 与 `g`(U+0067，Cambridge 用) 已归一化。

## 后续（尚未做）

- 版权：音频版权属 Cambridge，当前单人自用可接受；**对外分发前需先确认授权**（与 asset 库携带个人数据同一类约束）。App 里实际分发的 18 个 Cambridge 录音同理。

---

# tool/fetch-phonetics-yyb.ts — 音标发音抓取（英语音标网 → App assets，48 个齐全）

抓 [英语音标网](https://yingyuyinbiao.com/) 的 [英语元音(20个)](https://yingyuyinbiao.com/英语元音/) + [英语辅音(28个)](https://yingyuyinbiao.com/英语辅音/) 两页上的 48 个音标发音。**已退役**：产出的是 2026-09-21 之前在用的那套（30 个本站 + 18 个 Cambridge 补齐，音色不统一；例词无录音），现已被人工录音包取代（见上节）。符号体系（DJ / 国内教材）与 `phonicsGroups` 对齐这点仍然成立。

## 用法

```bash
cd impl/server
bun run tool/fetch-phonetics-yyb.ts -- [--out <dir>] [--force] [--cambridge <dir>] [--batch N] [--delay MS]
```

| 参数 | 缺省 | 说明 |
|------|------|------|
| `--out` | `impl/app/flutter/assets/phonetics` | 输出目录 |
| `--force` | 否 | 重下已存在的文件；缺省**跳过已存在**（断点续跑：失败重跑只发缺口那几个请求） |
| `--cambridge` | 无（不补齐） | Cambridge 源目录（`fetch-phonetics.ts` 在别处的输出），用于补本站已删除的 18 个。**不传时只产出本站能给的 30 个**——见下 |
| `--batch` / `--delay` | 6 / 150 | 同 `fetch-phonetics.ts` |

整份重建（含那 18 个补齐）：

```bash
bun run tool/fetch-phonetics.ts --out /tmp/cambridge-phonetics
bun run tool/fetch-phonetics-yyb.ts --cambridge /tmp/cambridge-phonetics
```

重跑不会丢来源标注：已存在的文件不重下，`source` 从上一轮 manifest 读回（`readPrevSources`）。

## 关键事实：本站 48 个里有 18 个是死链

页面 `<td>` 里的播放按钮挂着 48 个 mp3 地址，但**其中 18 个文件在服务器上已被删除**：

- WordPress 媒体库（`/wp-json/wp/v2/media?media_type=audio`）里**还有**这些附件的记录（如 `2021/01/ə-long.mp3`，id 712），
- 但请求该地址返回的是 **WP 的 404 页**（响应头 `x-powered-by: PHP/8.3.33` + `link: wp-json`，说明静态层没找到文件、回落到 PHP 路由），
- 换客户端（curl / 页面内 fetch）、换编码（百分号/裸字节/大小写/二次编码/加查询串）、翻同目录旧副本（2020/08 那批）都拿不到。

死链的规律：**文件名以非 ASCII 字符开头**的那些——元音 `ɜː ɔː ə ɒ ʊ ʌ æ ɔɪ əʊ ɪə ʊə`、辅音 `θ ð ʃ tʃ ʒ dʒ ŋ`，共 18 个。ASCII 开头的（`I-long.mp3`、`eɪ.mp3`、`p_sound.mp3`…）都在。**别去"修"这个 404——不是抓取姿势问题，是源站没文件了。**

所以：本站实际产出 **30 个**，另 18 个由脚本自动从 Cambridge 源复制补齐（取 UK，与本站同为英式），`manifest.json` 的 `source` 字段逐条标明 `yyb` / `cambridge`。补齐只填空缺，不覆盖本站录音。

## 执行流程

1. 依次软导航两页（`gotoAndWait`：每次先回 `about:blank`，避免用上一页的 DOM 误判就绪），轮询 `input.myButton_play` 出现。
2. 页面内逐 `<td>` 解析：音频地址在播放按钮的 `onclick="play_mp3('play','<id>','<mp3地址>',…)"` 里（本站用 compact-wp-audio-player 插件，音频不挂 `<audio>` 标签）。符号取该单元格里**播放器容器之前**的第一处 `/…/`，例词取**之后**的文本——用 `compareDocumentPosition` 判先后，不能靠"走过容器内的文本节点"（容器里全是 input/div，一个文本节点都没有）。
3. 页面内串行下载 → base64 → 外层落盘 → 校验 mp3 头（同 Cambridge 源，见 `lib/webview.ts` 的 `looksAudio`）。
4. `fillFromCambridge`：把仍未落盘的缺口按**归一化符号**从 Cambridge manifest 里找 `uk.sound` 复制过来。
5. 写 `manifest.json`，打印产出与覆盖率。

## 输出

```
assets/phonetics/
  v01.mp3 … v20.mp3   # 元音，序号 = 页面顺序（长元音→短元音→双元音）
  c01.mp3 … c28.mp3   # 辅音，序号 = 页面顺序（清浊相对 20 + 其它 8）
  manifest.json
```

**为什么不用源站的 basename**（Cambridge 源是沿用的）：源站用的是 `I-long.mp3` / `ə-long.mp3` 这类含 IPA 字符的名字——macOS 默认大小写不敏感（`i` 与 `I` 会撞）、Unicode 还有 NFC/NFD 归一化差异，manifest 里的名字可能和实际文件名对不上。文件名只当不透明句柄，**符号 → 文件以 manifest 为准**；源站原名保留在 `src` 字段备查。

`manifest.json` 每条：

| 字段 | 说明 |
|------|------|
| `symbol` | 源站写法（如 `i:`、`əU`）——保留原样，便于和源站页面核对 |
| `normalized` | 归一化到 App 写法（`iː`、`əʊ`；`:`→`ː`、`ai`→`aɪ`、`a:`→`ɑː`、`ɡ`→`g`）——**App 按这个字段查表** |
| `keyword` | 例词（源站页面上的，如 `see/she`、`thank /θæŋk/`） |
| `table` | 页内分组（如 `双元音`） |
| `file` | 落盘文件名 |
| `source` | `yyb`（本站录音）或 `cambridge`（补齐） |
| `src` | 该文件来自哪个源文件（yyb 站内 basename / Cambridge basename） |
| `page` | 所属页面 URL |

重跑时"已存在"的文件不重下，来源从上一轮 manifest 读回，不会被误标成本站录音（`readPrevSources`）。

## 覆盖率：48 / 48

App 需求清单同样**不在脚本里重复维护**，从 `lib/ui/reference/reference_data.dart` 的 `phonicsGroups` 正则读出后比对。48 个符号全部命中——包括 Cambridge 拿不到的 `/tr/ /dr/ /ts/ /dz/`（本站有独立录音）。

App 侧还有一道守门测试：`test/ui/reference/reference_data_test.dart` 断言 manifest 覆盖全部 48 个符号、且每个文件真实存在且非空。换素材时对不上就直接红。

## 后续（尚未做）

- **音色不统一**：48 个里 30 个是本站播音员、18 个是 Cambridge 播音员，交叉听能听出来。要统一只能换源（本站已无文件）。
- 版权：音频版权分属英语音标网与 Cambridge，当前单人自用可接受；**对外分发前需先确认授权**。

---

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
