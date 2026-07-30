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
  impl/app/android  # Contexta的Android版本实现
```

### 实现代码中的文档目录

```
impl/app/android/app/docs/           # 系统设计文档（参照代码生成，反映当前系统的现况，供参考）
impl/app/android/app/temp_docs/      # 临时计划文档（执行复杂任务前编写的计划，执行完后可删除）
```

### 文档布局（根目录 `/`）
文档存储在根目录，按类别组织：
- **产品** — 产品需求文档、用户故事
- **原型** — 原型图、线框图、交互稿
- **设计** — 架构设计、数据库设计、API 设计
- **技术约束** — 技术选型、约束条件、权衡决策

### 实现代码（`impl/`）
所有源代码位于 `impl/` 下。代码主要由 AI 根据根目录的文档生成。实现技术栈尚未确认 — 遇到技术选型决策时标注为待定。

## 入门

当前为全新项目，尚无实现代码。开发将在文档（产品、设计、技术约束）定稿后开始。

## 核心原则

- **语境优先**：通过阅读真实文章习得词汇，而非孤立记忆
- **文档驱动开发**：根目录的文档定义 `impl/` 要构建的内容
- **AI 生成代码**：实现主要由 AI 基于文档生成
