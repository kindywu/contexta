# 参考页音标自身音 + 单词放大可点设计

日期：2026-08-01
状态：已批准（用户确认「直接部署在真机」）

## 背景

参考页（`ReferenceScreen`）音标 Tab 弹窗点「发音」只读例词（如 `see`），不读音标自身的声音。字母表 Tab 弹窗已支持先读字母名再读例词（`A. Apple`，见 `2026-08-01-alphabet-speak-order-design.md`）。用户在真机体验时希望音标也能**先发自身的音**，且弹窗内**单词放大、点击单词发音**。

## 需求

- 范围：参考页**字母表 + 音标**两个 Tab 的弹窗
- 点击弹窗大字（56sp 字符）：字母格读字母名（`A a` → `A`）；音标格读自身拟音（`/iː/` → `ee`）
- 弹窗例词放大为珊瑚色可点击，点击读例词（`Apple` / `see`）
- 「发音」按钮行为不变：字母格 `A. Apple`，音标格 `see`
- 不受影响：语法 Tab（无发音）、网格卡片、阅读页、生词本等

## 约束

TTS 无法直接朗读 IPA 符号（`/iː/` 会被读成字母 `i`），因此需要为 48 个音标各配一个 TTS 可读的**拟音文本**。拟音为近似值，标「验证」的条目需真机试听调整——表结构固定，值可调。

## 设计

### 弹窗交互（字母表 / 音标共用）

```
┌───────────────────────────┐
│  ✕                        │
│   A a   /   /iː/          │ ← 56sp 大字，可点击：字母→读字母名 A；音标→读拟音 ee
│   /eɪ/  /  单元音 (12)    │ ← 读音行不变
│   Apple      /  see       │ ← 例词 headlineSmall 珊瑚色，可点击读例词
│   苹果（labelSmall Muted）  │ ← 中文释义拆下行小字
│  ┌──────────────┐         │
│  │ 发音（行为不变）│         │
│  └──────────────┘         │
└───────────────────────────┘
```

| 元素 | 行为 |
|------|------|
| 大字（56sp） | 点击读自身音；音标格查映射表，**映射缺失兜底读例词** |
| 例词 | `headlineSmall`（24sp）+ `Primary` 珊瑚色（设计系统「珊瑚色只用于可操作元素」token），点击读例词 |
| 中文释义 | 从例词行拆出，下行 `labelSmall` Muted（中英混排放大后失衡） |
| 发音按钮 | 不变，仍走 `speakTextFor(cell)` |

### 拟音映射表（48 条）

新增 `phonemeSoundMap: Map<String, String>`，key 为音标原文（含斜杠），value 为拟音文本。数据放 `ReferenceScreen.kt` 顶层私有常量，不污染 `PhonicsItem` 数据模型。

**单元音 (12)**

| 音标 | 拟音 | 备注 |
|------|------|------|
| /iː/ | ee | |
| /ɪ/ | ih | 验证 |
| /e/ | eh | |
| /æ/ | ack | TTS 无法单独读短音 a，加尾音 k（/æk/，如 back） |
| /ɑː/ | ah | |
| /ɒ/ | aw | 近似（美音引擎多为 /ɑː/） |
| /ɔː/ | or | |
| /ʊ/ | ook | 如 book（/ʊk/），加尾音 k |
| /uː/ | oo | |
| /ʌ/ | uh | |
| /ɜː/ | er | |
| /ə/ | uh | 与 /ʌ/ 同音近似（弱读元音） |

**双元音 (8)**：/eɪ/→ay · /aɪ/→eye · /ɔɪ/→oy · /aʊ/→ow · /əʊ/→oh · /ɪə/→ear · /eə/→air · /ʊə/→oor（验证）

**爆破音 (6)**：/p/→puh · /b/→buh · /t/→tuh · /d/→duh · /k/→kuh · /ɡ/→guh

**摩擦音 (10)**：/f/→fuh · /v/→vuh · /θ/→thuh（验证）· /ð/→thuh（验证）· /s/→suh · /z/→zuh · /ʃ/→shuh · /ʒ/→zhuh（验证）· /h/→huh · /r/→ruh

**破擦音 (6)**：/tʃ/→chuh · /dʒ/→juh · /tr/→truh（验证）· /dr/→druh（验证）· /ts/→tsuh（验证）· /dz/→dzuh（验证）

**鼻辅音 (3)**：/m/→muh · /n/→nuh · /ŋ/→nguh（验证）

**舌侧音 (1)**：/l/→luh　**半元音 (2)**：/j/→yuh · /w/→wuh

### 代码结构

- `ReferenceScreen.kt`：
  - 新增 `phonemeSoundMap`（私有常量）+ 顶层纯函数 `phonemeOwnSound(phone: String): String?`（查映射，供点击大字用）
  - 弹窗大字加 `clickable`：字母格 `speak(char.first().toString())`；音标格 `speak(phonemeOwnSound(char) ?: example)`
  - 例词放大 + 珊瑚色 + `clickable` 读例词；中文释义拆下行
  - `speakTextFor` 不变
- `ReferenceViewModel` 不动（已有 `speak(text)`）

### 测试（`SpeakTextTest.kt`）

1. **映射完整性**：遍历 8 组 48 个音标，断言 `phonemeSoundMap` 全部覆盖（防漏配）
2. **抽样正确性**：如 `/iː/`→`ee`、`/b/`→`buh`、`/æ/`→`ack`
3. **兜底逻辑**：未知音标 `phonemeOwnSound` 返回 null（点击时兜底读例词）
4. 既有 `speakTextFor` 测试保持不变

## 验证

1. `./gradlew :app:testDebugUnitTest` 单元测试通过
2. `./gradlew :app:installDebug` 安装真机
3. 真机逐条试听 48 个拟音，调整「验证」条目值
4. 参考页 → 音标 Tab → 点 `/iː/` 格子 → 点大字听到 `ee`、点例词听到 `see`、点「发音」仍只读 `see`
5. 参考页 → 字母表 Tab → 点 `A a` 格子 → 点大字听到 `A`、点例词听到 `Apple`

## 文档同步

- `app/docs/UI设计系统.md` 5.3 参考页弹窗描述：更新为「大字可点发音（字母读字母名/音标读拟音）+ 例词放大珊瑚色可点 + 中文拆行」
