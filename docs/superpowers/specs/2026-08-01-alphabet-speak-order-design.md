# 字母表发音顺序设计（先读字母名，再读例词）

日期：2026-08-01
状态：已批准

## 背景

参考页（`ReferenceScreen`）字母表 Tab 展示 26 个字母卡片。点击字母格子弹出详情弹窗（字母、音标、例词、中文），弹窗内有"发音"按钮，点击后 TTS 朗读。

## 现状问题

当前"发音"按钮只朗读例词（如 `Apple`），不读字母本身的发音（字母名 `A`）。用户在真机体验时希望教学式发音：**先读字母名，再读例词**。

## 需求

- 范围：仅参考页**字母表** Tab 的弹窗"发音"按钮
- 行为：点击"发音"后，TTS 先读字母名（如 `A`），停顿后读例词（如 `Apple`），即 `A. Apple`
- 触发方式不变：仍为弹窗内"发音"按钮
- 不受影响：音标 Tab（继续只读例词，如 `see`）、语法 Tab（无发音）、阅读页、生词本等其他发音功能

## 设计

### 方案选择

采用**方案 A：弹窗按钮处拼接发音文本**（用户已批准）。

- 改动文件：`app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt`
- 改动点：弹窗"发音"按钮 `onClick`（现约第 174 行）

```kotlin
onClick = {
    val text = if (cell.isPhonetic) cell.example
               else "${cell.char.first()}. ${cell.example}"
    viewModel.speak(text)
}
```

### 设计要点

| 要点 | 说明 |
|------|------|
| 字母名来源 | `cell.char` 格式为 `"A a"`（大写+小写），取 `char.first()` 得到大写字母 |
| 停顿 | 句号 `". "` 让 TTS 自然停顿，先读字母名再读例词 |
| 分支条件 | `isPhonetic == false` 时拼接；音标格（`isPhonetic == true`）保持只读 `cell.example` |
| 全字母覆盖 | 26 个字母全部生效，包括 `"W w"` → `W. Water`、`"X x"` → `X. X-ray` |

### 明确不做的

- 不改 `TtsEngine` / `TtsEngineImpl`（TTS 层不感知字母语义）
- 不改 `ReferenceViewModel`
- 不加数据字段（不污染 `ReferenceCellData` / `AlphabetItem`）
- 不改变触发方式（不做点击格子直接发音）
- 音标 Tab 不"先读音标再读例词"（IPA 符号 TTS 无法朗读）

## 验证

1. `./gradlew :app:installDebug` 构建安装到真机
2. 参考页 → 字母表 → 点 "A a" 格子 → 点"发音" → 听到 `A. Apple`
3. 抽查多字母音标长度的 "W w"（`W. Water`）与 "X x"（`X. X-ray`）
4. 音标 Tab → 点格子 → 点"发音" → 仍只读例词（如 `see`）
