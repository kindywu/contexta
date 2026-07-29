---
version: draft
name: Reference Screen Grid Redesign
description: 将字母表和音标标签从扁平列表布局改为紧凑网格布局，提升信息密度和视觉质感
---

## 概述

重新设计「参考」页面中的「字母表」和「音标」两个标签的内容区布局，解决原列表显得稀疏的问题。语法标签保持不变。

## 设计原则

- **信息密度优先**：一屏可见更多字母/音标，减少滚动
- **卡片质感**：每个条目有分明边界和圆角，整体像一张参考海报
- **保持交互**：点击卡片播放发音
- **继承现有主题**：使用 `Color.kt` 已有的颜色 tokens，与应用保持一致

## 字母表标签

### 布局

- **4列网格**（`.chunked(4)` + Row + weight(1f) 实现）
- 26个字母约7行铺满，无大量空白
- 首行字母前可加一行网格标题行（可选）

### 卡片内容

每张卡片从上到下：

1. **字母字符** — `MaterialTheme.typography.titleMedium`，`FontWeight.SemiBold`，`Foreground` 色
2. **音标** — `MaterialTheme.typography.bodySmall`，`Meta` 色（#87867F）
3. **右下角播放指示** — 一个珊瑚色小圆点（`Accent`，6dp直径）

### 卡片样式

- 背景：`Surface`（#FAF9F5）
- 圆角：`RoundedCornerShape(8.dp)`
- 内边距：水平10dp，垂直10dp
- 点击反馈：背景短暂变为 `Accent` 的10%透明度浅底，点击后恢复
- 点击动作：TTS 朗读该字母的示例词

## 音标标签

### 布局

- **3列网格**
- 分为两大区：**元音 (20个)** 和 **辅音 (28个)**
- 每区上方有分区标题行

### 分区标题

- 文字：`MaterialTheme.typography.titleSmall`，`FontWeight.SemiBold`，`Accent` 色
- 左侧带一条 `Accent` 色竖线装饰（2dp宽，16dp高）
- 上下内边距：12dp

### 卡片内容

每张卡片从上到下：

1. **音标字符** — `MaterialTheme.typography.bodyMedium`，`Foreground` 色
2. **示例词** — `MaterialTheme.typography.bodySmall`，`ForegroundSecondary` 色（#3D3D3A）
3. **完整音标** — `MaterialTheme.typography.labelSmall`，`Muted` 色（#5E5D59）

### 卡片样式

**元音区：**
- 背景：`SurfaceWarm`（#E8E6DC）— 暖色底，与元音的 warm 属性呼应

**辅音区：**
- 背景：`Surface`（#FAF9F5）— 中性底

- 统一圆角：`RoundedCornerShape(8.dp)`
- 内边距：水平8dp，垂直10dp
- 点击动作：TTS 朗读示例词

## 交互

- 点击卡片整体（而非仅按钮）触发 TTS 朗读
- 每张卡片保持 `clickable` 修饰符，不需要额外 Icon 按钮
- 点击反馈通过 `indication` 实现（Material3 默认 ripple）

## 不做的事项

- 语法标签内容保持原样
- 顶栏标题、标签切换栏保持原样
- ReferenceViewModel 不需要改动
- 数据（alphabetData, phonicsVowels, phonicsConsonants）不需要改动
- 不引入新的第三方依赖

## 实现文件

只修改一个文件：
- `impl/app/android/app/src/main/java/com/ak/contexta/ui/reference/ReferenceScreen.kt`

提取可复用的 `AlphabetGridCard` 和 `PhonicsGridCard` composable 函数，放入同一文件（由于逻辑简单，不拆出额外文件）。
