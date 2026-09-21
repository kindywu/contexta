# 字母表（参考页「字母表」tab）

## 主题定位

参考页「字母表」tab 的全部内容：26 个字母格、字母详情弹层（**该字母的常见读音**）、两条连播（整张字母表、单个字母的读音）。

音频素材分两路：读音本身与「例词取自音标库」的那些例词放的就是音标那 48 个随包录音（`assets/phonetics/s*.mp3` / `w*.mp3`），素材来路与转码规格见 [phoneme-audio.md](phoneme-audio.md)；**「自带站点例词」的几条例词是 TTS 预生成的 `l*.mp3`**（见「素材来源」）；连播里的字母名走运行时 TTS，见 [tts-engine.md](tts-engine.md)。

## 业务功能线

```mermaid
flowchart TD
    A["字母表 tab"] --> B["26 格 4 列网格<br/>字母 + 字母名音标 + 「N 种读音」"]
    A --> C["顶部「连播全部 26 个字母」"]
    B --> D["字母详情弹层（底部弹层）：常见读音列表"]
    C --> E["逐字母：字母名 → 读音 → 例词"]
    D --> F["点读音 → 放读音录音"]
    D --> G["点例词 → 放例词录音"]
    D --> H["弹层内「连播这 N 种读音」"]
```

**网格**：每格三行——`A a`、字母名音标 `/eɪ/`（点击进弹层）、`5 种读音`（该字母有几种读法）。字母读音种类数从 1（B/F/H…）到 6（O/U）不等。

**弹层**（点字母格打开，底部弹层、内容可滚动）**只有一块内容**：小节头 `常见读音 (5)` + ▶/■ 连播按钮 + 读音行列表。字母名、字母表的例词（`Apple` / 中文 / 40sp 大字）与「发音」按钮都**不在弹层里**（2026-09-22 去掉：这块功能的重点是「这个字母能发哪些音」，字母名与例词是另一回事，混在一屏里反而喧宾夺主）。想听字母名走连播（它会先报字母名）。

**读音行**是这块功能的主角：音标 + 类别徽章 + 例词 + 例词音标，**两个点击区**（与音标格弹窗同款分工）：

| 点击区 | 行为 |
|--------|------|
| 左边音标 | 放**读音本身**的录音；没有录音的读音（X 的 `/ks/` `/gz/`）兜底读例词（IPA 绝不进 TTS） |
| 右边例词 | 放**例词录音**（音标库那套或 TTS 预生成那批）；录音缺了回退 TTS 读例词 |
| 弹层「连播这 N 种读音」 | 读音录音 → 停 1s → 例词录音，逐行往下读 |

- **类别徽章**：`硬音`/`软音`/`弱读`/`组合音`/`少数词` 才挂徽章（长按出解释），最常见的那类（`常见音`）不挂——满屏徽章等于没有徽章。徽章把 C/G 的硬软音规则（`cat` vs `city`、`go` vs `giant`）这类信息直接摆在行上。
- **例词默认来自音标库**：`/eɪ/` 那行的例词就是音标 tab 里 `/eɪ/` 的例词 `day`——因为录音是按音标符号给的（`w*.mp3`），换个词就没声音。代价是个别字母的例词不体现该字母的拼写（C 的 `/s/` 是 `sun` 而不是 `city`、G 的 `/dʒ/` 是 `jump` 而不是 `giant`、Q 的 `/k/` 是 `key`）——这是「例词要能发声」换来的，见「数据模型线」。
- **X 例外：三条例词都取自站点**。音标库那套在 X 上基本对不上（`/z/` 的例词是 `zoo`，根本不含 x），所以 X 的 `/ks/` `/gz/` `/z/` 分别自带站点例词 `box` / `exam` / `xylophone`（英式音标由本仓库补），这三条例词**用 App 自带的 KittenTTS 预生成了 `l01..l03.mp3`**（不是运行时 TTS——连播要精确等一段播完再进下一段，而 TTS 没有播完回调）。其中 `/ks/` `/gz/` 是两个音连读，连**读音本身**也没有录音（也无从拆开拼），这两行徽章标 `组合音`、注记「无单独录音」；`/z/` 的读音录音照放（音标库里有 `/z/`）。

**连播**（两种范围，同一套状态机）：

- **整张字母表**（tab 顶部按钮）：逐字母「TTS 读字母名 → 停 1s → 每个读音『录音 → 停 1s → 例词录音』」，**字母与字母之间再停 1s**。26 字母 63 条读音，整轮约 **4-5 分钟**。
- **弹层内「连播这 N 种读音」**：只有一组，读法同上但不读字母名之后那一拍之外的组间停顿（没有组边界）。
- 播放中当前格（整体连播时是字母格、弹层内是读音行）套珊瑚描边高亮，并自动滚到可见；再点同一个按钮即停。

**打断规则**（与音标 tab 完全一致，见 [phoneme-audio.md](phoneme-audio.md)「连播状态机」）：掐声（录音 + 字母名 TTS 都掐）、当前行不补读、迟到回调丢弃。触发停止的动作：再点同一按钮、点任意读音行、点任意字母格开弹层、关弹层、切 tab、离开页面。

## 技术实现线

### 数据：字母 → 读音（静态表 + 解析）

静态表 `letterSounds`（`lib/ui/reference/reference_data.dart`）只写**符号 + 类别**，例词不写——例词与例词音标由 `soundRowsOf(letter)` 按符号从 `phonicsGroups` 解析：

```mermaid
flowchart LR
    A["letterSounds（26 字母 / 63 条）<br/>'/eɪ/' → common / reduced / hard …"] --> C["soundRowsOf(letter)"]
    B["phonicsGroups（48 音标）<br/>'/eɪ/' → day /deɪ/"] --> C
    C --> D["LetterSoundRow<br/>phoneme / kind / example / exampleIpa<br/>hasAudio / isOwnExample"]
    E["X 自带站点例词<br/>'/ks/' → box、'/z/' → xylophone"] --> C
```

- 静态表**自带例词**的行（X 的三条）→ 用自带的词，`isOwnExample = true`：例词录音走 manifest 的 `letterWords` 段（TTS 预生成那批）。
- 否则例词、例词音标取自音标库 → `isOwnExample = false`（例词录音与 `w*.mp3` 一一对应）。
- `hasAudio`（**读音本身**有没有录音）另算：看符号在不在音标库里——X 的 `/z/` 是 `hasAudio = true` + `isOwnExample = true`（读音有录音、例词是站点的词）。
- 匹配时两侧都过 `normalizePhone`（去斜杠、`ɡ`↔`g`），与录音查表同一套归一化。
- `soundRowsOf` 对不存在的字母**抛 `StateError`**：数据写错要当场炸，不静默给空表。

**为什么从 `phonicsGroups` 解析而不是另抄一份例词**：抄一份必然漂移（音标 tab 换例词、录音包换词，字母表还留着旧词）；解析则「同一个音只有一个例词」是结构性保证，且那份例词与 `w*.mp3` 例词录音一一对应（由 `reference_data_test` 守门）。

### 素材来源：三条链路

```mermaid
flowchart LR
    A["读音本身 s01..s48.mp3<br/>音标库（ipa_web）"] --> D["assets/phonetics/"]
    B["例词 w01..w48.mp3<br/>音标库（人工录音包）"] --> D
    C["站点例词 l01..l03.mp3<br/>KittenTTS 预生成"] --> D
    E["manifest.json<br/>phonemes[] + letterWords[]"] --> F["AssetPhonemeAudio<br/>三张查表入口"]
    D --> F
```

第三条链路（`l*.mp3`）的生成步骤——换/加「自带例词」的读音行时按这个跑：

1. 在 `reference_data.dart` 的 `letterSounds` 里把该行写成自带例词（`example:` / `exampleIpa:`）。
2. `flutter test integration_test/generate_letter_words_test.dart -d <device>`：在设备上用 App 自带的 KittenTTS（micro 模型 + bella 音色，与参考页同嗓子）逐词合成，落到设备外部文件目录，**并停 30s 等 pull**（集成测试一结束应用就被卸载，外部目录随之消失，所以要边跑边拉）：

   ```bash
   adb pull /sdcard/Android/data/com.ak.contexta/files/letter_words /tmp/letter_words
   ```

3. 转 mp3 并落进 assets（设备上只出 wav：kittentts 不带 mp3 编码器，MP3 编码要 GPL/LGPL 的代码）：

   ```bash
   lame --quiet -b 64 -m m /tmp/letter_words/l01.wav assets/phonetics/l01.mp3
   ```

4. 把 `/tmp/letter_words/manifest-fragment.json` 的内容并进 `manifest.json` 的 `letterWords` 段。
5. `flutter test test/ui/reference/reference_data_test.dart`：守门「自带例词的行必须在 manifest 里有条目、词对得上、文件存在且非空」。

`impl/server/tool/import-phonetics-audio.ts` 的 `--phonemes-from` 与 `--zip` 两个模式都会**原样带过 `letterWords` 段**（换音标包不该把这批丢掉）。

### 播放链路

```mermaid
classDiagram
    class LetterSoundRow {
        +String phoneme
        +LetterSoundKind kind
        +String example
        +String exampleIpa
        +bool hasAudio
        +bool isOwnExample
        +String? note
    }
    class LetterPlayGroup {
        +String cellKey
        +List~LetterSoundRow~ rows
        +String letterName
    }
    class ReferenceController {
        +playLetterSound(row) Future~void~
        +playLetterExample(row) Future~void~
        +playLetterSequence(groups, onGroup, onRow) Future~void~
        -_playLetterRow(row, aborted) Future~void~
    }
    class PhonemeAudio {
        +play(phone)
        +playWord(phone)
        +playLetterWord(phone)
    }
    class ReferenceScreen {
        -String _playingKey
        -String _activeCell
        -String _activeSound
        -_toggleLetterSequence(key, groups)
        -_playSound(row) / _playExample(row)
    }
    LetterPlayGroup --* LetterSoundRow
    ReferenceController --> LetterPlayGroup
    ReferenceController --> PhonemeAudio
    ReferenceScreen --> ReferenceController
```

`PhonemeAudio` 三个入口对应三张表：`play` = 读音本身（`phonemes[].file`）、`playWord` = 音标库例词（`phonemes[].wordFile`）、`playLetterWord` = 字母读音行的站点例词（`letterWords[].file`）。**后两者不能合并**——同一个符号可以有两套例词：`/z/` 在音标库里是 `zoo`、在字母读音行里是 `xylophone`。

`letterSounds` →（`soundRowsOf`）→ `LetterSoundRow` →（`allLetterPlayGroups` / `letterPlayGroupOf`）→ `LetterPlayGroup`（`cellKey` 是网格格子标识 `'A a'`，`letterName` 取首字符给 TTS）。

单个点击区（点读音 / 点例词各一条独立路径，互不牵连）：

```mermaid
sequenceDiagram
    participant U as 用户
    participant S as _ReferenceCellModal
    participant C as ReferenceController
    participant A as AssetPhonemeAudio
    participant T as TtsEngine
    U->>S: 点左边的音标 /eɪ/
    S->>C: playLetterSound(row)
    C->>A: play('/eɪ/')
    A-->>U: 播放 s13.mp3（读音本身）
    Note over C,T: 没有读音录音（/ks/ /gz/）兜底 TTS 读例词——IPA 不进 TTS
    U->>S: 点右边的例词 day
    S->>C: playLetterExample(row)
    C->>A: playWord('/eɪ/')
    A-->>U: 播放 w13.mp3
    Note over C,A: 自带例词（X 三条）走 playLetterWord → l0N.mp3
```

连播里一行是两段连读（整张字母表连播在每格开头还多一段 TTS 字母名）：

```mermaid
sequenceDiagram
    participant C as ReferenceController
    participant T as TtsEngine
    participant A as AssetPhonemeAudio
    Note over C: 每个字母循环（字母之间停 1s）
    C->>C: onGroup → UI 高亮该字母格
    C->>T: speak('A')
    Note over C: 停 1s（TTS 没有播完回调，靠这一拍错开）
    loop 该字母的每条读音
        C->>C: onRow → UI 高亮该行
        C->>A: play(符号) → 停 1s → playWord / playLetterWord(符号)
    end
```

**字母名那一拍的来路**：TTS 没有「播放完成」回调（`TtsEngine.speak` 立刻返回，见 [tts-engine.md](tts-engine.md)），所以字母名与第一个读音之间**靠固定 1s 间隔错开**，而不是等播完。字母名比 1s 还长的（`W` `/ˈdʌbljuː/`）会让两段轻微叠上——已知取舍，换来的是不必给 TTS 加一套回调机制。

### 连播状态机

```mermaid
stateDiagram-v2
    [*] --> 空闲
    空闲 --> 播放中: 点「连播全部 26 个字母」/「连播这 N 种读音」\n（_playingKey = 范围, token++）
    播放中 --> 播放中: 每个字母 onGroup / 每条读音 onRow\n（_activeCell / _activeSound → 高亮 + ensureVisible）
    播放中 --> 空闲: 整轮读完（await 返回）
    播放中 --> 空闲: 再点同一按钮 / 点读音行 / 开弹层 / 关弹层\n切 tab / 页面 dispose（token++ + stopSequence）
```

`_playingKey` 的取值区分四条来源：`_allLettersKey`（整张字母表）、`_letterSeqKey(letter)`（弹层内单个字母）、音标 tab 的 `_allPhonicsKey` 与分组名。页面状态三个字段各管一段：`_playingKey` 决定按钮显示「连播」还是「停止」、`_activeCell` 是高亮的格子、`_activeSound` 是高亮的读音行。

## 数据模型线

无数据库实体。静态数据全在 `lib/ui/reference/reference_data.dart`：

| 数据 | 内容 |
|------|------|
| `LetterSoundKind` | 类别枚举，带中文标签与一句解释（徽章文案 + 长按提示） |
| `letterSounds` | 26 字母 / 63 条：符号 + 类别（+ X 三条自带站点例词与音标） |
| `AlphabetItem.soundCount` | 格子上的「N 种读音」 |
| `soundRowsOf(letter)` | 解析成 `LetterSoundRow`（例词来自音标库，组合音自带） |
| `allLetterPlayGroups` / `letterPlayGroupOf(letter)` | 连播分组（格子标识 + 读音行） |

音频资产两份，各有各的对应表：

| 资产 | 内容 | 查表 |
|------|------|------|
| `s01..s48.mp3` / `w01..w48.mp3` | 48 个音标本身 + 48 个音标库例词（随包真人录音） | `manifest.phonemes[]` |
| `l01..l03.mp3` | X 三条例词的 TTS 预生成录音（24kHz 单声道 64kbps） | `manifest.letterWords[]`（`phoneme` / `word` / `file`） |

数据来源是 [english-ipa.netlify.app](https://english-ipa.netlify.app) 的「字母读音」板块（音频同源 [resetsix/english-ipa](https://github.com/resetsix/english-ipa)）——**取「字母 → 读音符号 + 类别」这一层**；例词默认换成本 App 音标库那套（站点用的是美式音标 + 另一批例词，整批搬进来会与全 App 的英式体系打架，而且那些词没有随包录音），只有 X 三条保留站点例词（音标库的词在 X 上对不上，见「业务功能线」）。

## 错误处理与边界

| 场景 | 处理 |
|------|------|
| 读音不在录音库（组合音） | `hasAudio = false`：点读音不白等，直接读例词；行上注记「无单独录音」 |
| 自带例词的录音缺失 | `playLetterWord` 返回 false → 回退 TTS 读例词 |
| 音标库例词录音缺失 | `playWord` 返回 false → 同上回退 TTS |
| 读音录音启动失败 | 不白等那一拍，直接读例词 |
| 字母不在读音表 | `soundRowsOf` 抛 `StateError`（数据错误当场暴露，不静默降级） |
| 读音表与音标库漂移 | `reference_data_test` 直接红（符号覆盖 + 例词一致性 + 组合音白名单三重断言） |
| 自带例词缺 `letterWords` 条目 / 词对不上 / 文件不在 | `reference_data_test` 直接红（跑生成用例补上） |
| 旧版 manifest（没有 `letterWords` 段） | 解析返回空表 → 那几行回退 TTS，页面不崩 |
| 连播中途停止 | 掐声（录音 + 字母名 TTS）、当前行不补读、迟到回调丢弃 |
| 停止发生在字母名开口前 | 该字母连字母名都不读（`onGroup` 回调后立刻查令牌） |
| 播放中打开弹层 / 关弹层 | 都先 `stopSequence()`，声音不叠着响 |
| 离开页面 | `dispose` 里 `stopSequence()`（控制器引用在 `initState` 取一次，`dispose` 里不能再碰 `ref`） |

## 测试覆盖

| 测试 | 覆盖 |
|------|------|
| `test/ui/reference/reference_data_test.dart` | 26 字母都有读音表且顺序与字母表一致；每条读音要么在音标库里（有录音）要么在组合音白名单（自带例词）；非自带例词的行其例词 / 例词音标与音标库同符号一致；X 三条读音的顺序、例词（box / exam / xylophone）、音标与录音标记；自带例词在 manifest 有 `letterWords` 条目且词一致、文件存在且非空；未知字母抛错；连播分组 26 组、字母名取首字符、单字母分组 |
| `test/domain/audio/phoneme_audio_test.dart` | `letterWordClipsFromManifest`：解析、归一化、整段缺失 / 坏 JSON / 缺字段条目 |
| `test/data/audio/asset_phoneme_audio_test.dart` | `playLetterWord` 放的是 `letterWords` 那批（同一个 `/z/` 与音标库不串）；组合音只有例词录音；manifest 缺失时返回 false |
| `test/ui/reference/reference_controller_test.dart` | 点读音只放读音录音（TTS 不发声）；点例词只放例词录音；组合音点读音兜底 TTS 读例词；自带例词走 `playLetterWord`；自带例词 / 音标库例词录音缺失各自回退 TTS；单行点播不受停止影响；连播一行「读音录音 → 停一拍 → 例词录音」；读音没录音不白等；字母内连播（字母名 → 逐行，逐行回调）；字母名后那一拍；字母间那一拍且只停一次；空表直接结束；中途停止（掐录音 + 掐 TTS + 当前行不补读）；停止在字母名之前；整张字母表 26 组跑完（读音录音 / 音标库例词 / `letterWords` / TTS 各自的条数对得上） |
| `test/ui/reference/reference_screen_test.dart` | 格子上「N 种读音」；弹层是底部对齐、只有「常见读音」（字母名 / 例词 / 发音按钮都不在）；点读音出声、点例词出声（都不走 TTS）；组合音行徽章 / 注记 / 点读音兜底 TTS / 点例词走预生成录音；弹层内连播（高亮行、字母名先出声、停止复位）；关弹层即停；顶部「连播全部 26 个字母」（开播高亮 A 格、停止清除） |
| `integration_test/generate_letter_words_test.dart` | **生成用例**（不是回归测试）：合成自带例词的 wav + manifest 片段，见「素材来源」 |
