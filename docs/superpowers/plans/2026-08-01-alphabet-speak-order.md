# 字母表发音顺序实现计划（先读字母名，再读例词）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 参考页字母表弹窗点"发音"时，TTS 先读字母名（如 `A`），停顿后读例词（如 `Apple`）。

**Architecture:** 在 `ReferenceScreen.kt` 添加顶层纯函数 `speakTextFor(cell: ReferenceCellData)` 计算发音文本（字母格 `"A. Apple"`，音标格原样返回例词），弹窗"发音"按钮调用它。纯函数可单元测试（同包可见，与 `GrammarData.kt` 的 `grammarGroups` 模式一致）。

**Tech Stack:** Kotlin, Jetpack Compose, JUnit4（`org.junit.Assert.assertEquals`，反引号测试名，参照 `GrammarDataTest.kt` 风格）。

## Global Constraints

- 不改 `TtsEngine` / `TtsEngineImpl` / `ReferenceViewModel` / `ReferenceCellData` / `AlphabetItem`
- 音标格（`isPhonetic == true`）发音文本保持原样（只读例词）
- 字母名取 `cell.char.first()`（`"A a"` → `A`，`"W w"` → `W`）
- 拼接格式固定为 `"${letter}. ${example}"`（句号 + 空格产生 TTS 自然停顿）
- 验证时构建安装真机（设备 `25053RT47C`，`adb devices` 确认在线）

---

### Task 1: 字母表发音文本拼接（测试先行）

**Files:**
- Create: `impl/app/android/app/src/test/java/com/ak/contexta/ui/reference/SpeakTextTest.kt`
- Modify: `impl/app/android/app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt:174`（弹窗"发音"按钮 onClick）
- Modify: `impl/app/android/app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt`（文件末尾新增顶层函数）

**Interfaces:**
- Consumes: `ReferenceCellData(char: String, reading: String, example: String, exampleCn: String, isPhonetic: Boolean)` — 已存在于 ReferenceScreen.kt
- Produces: `fun speakTextFor(cell: ReferenceCellData): String` — 顶层函数，同包可见，返回 TTS 朗读文本

- [ ] **Step 1: 写失败测试**

创建 `impl/app/android/app/src/test/java/com/ak/contexta/ui/reference/SpeakTextTest.kt`：

```kotlin
package com.ak.contexta.ui.reference

import org.junit.Assert.assertEquals
import org.junit.Test

class SpeakTextTest {

    @Test
    fun `alphabet cell speaks letter name then example`() {
        val cell = ReferenceCellData(
            char = "A a", reading = "/eɪ/", example = "Apple", exampleCn = "苹果", isPhonetic = false
        )
        assertEquals("A. Apple", speakTextFor(cell))
    }

    @Test
    fun `multi-letter char uses uppercase first letter`() {
        val w = ReferenceCellData(
            char = "W w", reading = "/ˈdʌbljuː/", example = "Water", exampleCn = "水", isPhonetic = false
        )
        assertEquals("W. Water", speakTextFor(w))
        val x = ReferenceCellData(
            char = "X x", reading = "/eks/", example = "X-ray", exampleCn = "X光", isPhonetic = false
        )
        assertEquals("X. X-ray", speakTextFor(x))
    }

    @Test
    fun `phonetic cell speaks example only`() {
        val cell = ReferenceCellData(
            char = "/eɪ/", reading = "单元音 (12)", example = "see", exampleCn = "", isPhonetic = true
        )
        assertEquals("see", speakTextFor(cell))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run（在 `impl/app/android` 下）：

```bash
./gradlew :app:testDebugUnitTest --tests "com.ak.contexta.ui.reference.SpeakTextTest" --console=plain
```

Expected: BUILD FAILED — `unresolved reference: speakTextFor`（函数尚未定义）。确认是编译失败而不是测试失败即可。

- [ ] **Step 3: 实现纯函数并接线**

在 `impl/app/android/app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt` 末尾（`phonicsGroups` 定义之后）新增顶层函数：

```kotlin
/** 发音文本：字母格先读字母名再读例词（句号停顿），音标格只读例词 */
fun speakTextFor(cell: ReferenceCellData): String =
    if (cell.isPhonetic) cell.example else "${cell.char.first()}. ${cell.example}"
```

修改弹窗"发音"按钮（现 `ReferenceScreen.kt:172-176`）：

```kotlin
            // Speak button
            AppButton(
                text = "发音",
                onClick = { viewModel.speak(speakTextFor(cell)) },
                modifier = Modifier.fillMaxWidth()
            )
```

- [ ] **Step 4: 运行测试确认通过**

Run（在 `impl/app/android` 下）：

```bash
./gradlew :app:testDebugUnitTest --tests "com.ak.contexta.ui.reference.SpeakTextTest" --console=plain
```

Expected: BUILD SUCCESSFUL，3 个测试全部通过。同时跑一次参考页既有测试确认无回归：

```bash
./gradlew :app:testDebugUnitTest --tests "com.ak.contexta.ui.reference.*" --console=plain
```

Expected: BUILD SUCCESSFUL（GrammarDataTest + SpeakTextTest 全过）。

- [ ] **Step 5: 构建并安装真机验证**

Run（在 `impl/app/android` 下）：

```bash
adb devices
./gradlew :app:installDebug --console=plain
```

Expected: 设备 `25053RT47C` 在线，`Installed on 1 device.`。然后人工验证：
1. 打开应用 → 参考 → 字母表 → 点 "A a" 格子 → 点"发音" → 听到 `A. Apple`
2. 点 "W w" 格子 → 点"发音" → 听到 `W. Water`（多字母音标长度字母抽查）
3. 切到音标 Tab → 点 `/eɪ/` 格子 → 点"发音" → 只读 `see`（无字母名前缀）

- [ ] **Step 6: 提交**

```bash
cd /Users/kindy/Githubs/contexta
git add impl/app/android/app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt \
        impl/app/android/app/src/test/java/com/ak/contexta/ui/reference/SpeakTextTest.kt
git commit -m "feat: 字母表发音先读字母名再读例词（A. Apple）+ SpeakTextTest

Co-Authored-By: Claude <noreply@anthropic.com>"
```
