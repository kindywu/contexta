# 设置修改次日生效机制

## 动机

用户修改"英文水平"或"每日文章数量"后，不应影响当前的 `daily_learning` 记录（当天已分配的文章批次）。修改应在第二天自动生效。

同时，修改难度应触发后台生成，确保第二天有对应难度的 READY 批次可用，避免用户等待。

## 设计方案

### 交互流程

#### 难度修改

```
用户点开英文水平选择器 → 选择新等级
  → SettingsPickerDialog 关闭
  → 弹出确认弹窗：
       ┌────────────────────────────────┐
       │ 修改英文水平                    │
       │                                │
       │ 此设置将在明天生效，            │
       │ 今天的学习不受影响。            │
       │                                │
       │    [取消]       [确认修改]      │
       └────────────────────────────────┘
  → 确认 → 写入 DB + triggerNextBatch（为新难度生成批次）
  → 取消 → 恢复原值
```

#### 篇数修改

```
用户点击 ± 按钮
  → 弹出确认弹窗（含当前值 → 新值）：
       ┌────────────────────────────────┐
       │ 修改每日文章数量                │
       │                                │
       │ 当前：3篇 → 调整至：5篇        │
       │                                │
       │ 此设置将在明天生效，            │
       │ 今天的学习不受影响。            │
       │                                │
       │    [取消]       [确认修改]      │
       └────────────────────────────────┘
  → 确认 → 写入 DB（不触发生成）
  → 取消 → 恢复原值
```

#### ℹ️ 信息提示

难度和篇数设置项旁增加 ℹ️ 图标，点击弹出说明：

```
       ┌────────────────────────────────┐
       │ ⚙️ 设置说明                    │
       │                                │
       │ 难度和篇数的修改将在            │
       │ 第二天自动生效，                │
       │ 不会影响今天的学习。            │
       │                                │
       │        [知道了]                │
       └────────────────────────────────┘
```

### 受影响的文件

| 文件 | 变更 |
|---|---|
| `SettingsUiState` | 新增 showLevelInfoDialog, showCountInfoDialog, showLevelConfirmDialog, showCountConfirmDialog, pendingLevel, pendingCount |
| `SettingsViewModel` | 新增 requestLevelChange / confirmLevelChange / cancelLevelChange, request / confirm / cancelCountChange |
| `SettingsScreen` | 新增 ℹ️ 图标组件、信息弹窗组件、确认弹窗组件；篇数改为请求式交互 |

### 数据流

- 确认修改后，`SettingsRepository` 写入 SQLite（`user_settings` 表）
- 难度修改额外调用 `TriggerNextBatchUseCase`（检查新难度是否有 READY 批次，没有则创建并调度 Worker）
- 篇数修改仅写入 DB，**不触发**生成（篇数在 `daily_learning.dailyCountSnapshot` 中体现）
- 第二天用户打开 App，`StartupOrchestrationUseCase` 自动按新设置匹配批次
