# 文章生成流程图

## 整体流程

```mermaid
flowchart TB
  subgraph scheduler["调度层 GenerationScheduler"]
    A["enqueueUniqueWork(batchId, KEEP)"] --> B
  end

  subgraph worker["Worker ArticleGenerationWorker.doWork()"]
    B["doWork()"] --> C{"claimBatch()<br/>UPDATE batch SET status='GENERATING'<br/>WHERE status='PENDING'"}

    C -- "CAS 成功" --> D["✅ claim 成功"]
    C -- "CAS 失败<br/>(batch 已不是 PENDING)" --> E["return Result.success()<br/>⛔ 放弃重试"]:::fail

    D --> F["generateArticles(batchId)"]
  end

  subgraph usecase["文章生成 GenerateArticlesUseCase"]
    F --> G["getArticles(batchId)<br/>读取所有文章"]
    G --> H{"for each article"}

    H --> I{"status == SUCCESS?"}
    I -- "是" --> J["continue 跳过"]:::skip
    I -- "否" --> K{"claimArticle()<br/>CAS: WHERE status IN<br/>('PENDING','TIMEOUT','FAILED')"}

    K -- "CAS 成功" --> L["LLM 调用生成"]
    K -- "CAS 失败" --> J

    L -- "成功" --> M["completeArticle()<br/>写入 title + paragraphs"]
    L -- "PipelineBlocking 异常" --> N["fatalArticle()<br/>markBatchBlocked()<br/>throw"]:::fail
    L -- "其他异常" --> O["failArticle()<br/>(TIMEOUT/FAILED)"]:::fail

    M --> J
    O --> J
    N --> P

    J -- "所有文章遍历完" --> Q{"检查批次"}

    Q --> R{"hasFatalArticle()?"}
    R -- "有" --> S["⏸ 保持 GENERATING<br/>管道阻塞"]:::blocked
    R -- "无" --> T{"isBatchComplete()?<br/>total == success?"}

    T -- "是" --> U["✅ markBatchReady()<br/>SET status='READY'"]
    T -- "否" --> V["⏸ 保持 GENERATING<br/>还有未完成文章"]:::waiting
  end

  U --> W["return Result.success()"]:::success
  S --> W
  V --> W

```

## 中断场景分析

```mermaid
flowchart LR
  subgraph scenario1["场景 A: Worker 被 kill<br/>部分文章已生成"]
    direction TB
    A1["Worker 中断<br/>claimBatch ✅<br/>部分文章 ✅<br/>部分文章 GENERATING/PENDING"] --> A2{"Worker 重试?"}

    A2 -- "WorkManager 重试" --> A3["claimBatch() → ⛔ 失败<br/>(batch 已是 GENERATING)<br/>return success，放弃"]:::gap
    A2 -- "App 重启" --> A4["StartupOrchestrationUseCase"]

    A4 --> A5["✅ reconcileOrphanArticles()<br/>文章 GENERATING → PENDING"]
    A5 --> A6["⚠️ batch 状态未重置<br/>仍为 GENERATING"]
    A6 --> A7["findNextReadyBatch() → null<br/>(只查 status='READY')"]:::gap
    A7 --> A8["NeedsInitialBatch<br/>创建 batch 7"]
  end

  subgraph scenario2["场景 B: 全部文章已生成<br/>crash 在 markBatchReady 前"]
    direction TB
    B1["所有文章 SUCCESS ✅<br/>batch GENERATING<br/>差 11ms 写 READY"] --> B2{"Worker 重试?"}

    B2 -- "WorkManager 重试" --> B3["claimBatch() → ⛔ 失败<br/>return success，放弃"]:::gap
    B2 -- "App 重启" --> B4["同场景 A<br/>→ 创建新批次"]:::gap
  end

  classDef gap fill:#f96,stroke:#c00,stroke-width:2px
  classDef success fill:#9f9,stroke:#090
```

## 缺口总结

| 中断位置 | 文章状态 | 批次状态 | 恢复结果 |
|---------|----------|---------|---------|
| claim 后，生成中 | 部分 SUCCESS，部分 GENERATING | GENERATING | ⛔ 批次被废弃，文章白生成 |
| 全部生成完，未 markBatchReady | 全 SUCCESS | GENERATING | ⛔ 差一步 READY，批次被废弃 |

**当前逻辑不能解决中断重入**，原因是：

1. **claimBatch CAS 太严格** — 重试时 batch 已是 GENERATING，直接 return success 放弃
2. **reconcileOrphanArticles() 只重置文章** — 批次状态没重置回 PENDING
3. **生成逻辑没有"断点续传"** — 不支持已有的文章就不再生成了
