/// 内容分类 → 难度映射（对照 Kotlin ArticlePrompts.kt 的 categoryToDifficulty）。
///
/// 2026-08-13（计划 B Task 6）：本地文章生成管道移除，本文件只保留
/// categoryToDifficulty（首页/查词链路按分类映射难度）；
/// buildArticleSystemPrompt/buildArticleUserPrompt/parseArticleLlmResponse
/// 与文章生成 prompt 模板一并删除。
/// 2026-08-14（计划 B Task 7）：查词远程化，word_prompts.dart 一并删除。
///
/// **词表以服务端为准**（`impl/server/src/engine/schema.ts` 的 Category 枚举，
/// 分类与难度是 1:1：LOW = 生活场景/日常对话/简易故事，MEDIUM = 新闻/说明/议论/
/// 个人随笔，HIGH = 学术摘要/辩论/法律文书/艺术评论）。服务端同步落库的是
/// **小写 snake_case**（`daily_conversation`…），而本地生成管道时代（≤2026-08-13）
/// 的存量行、asset 种子库存的是 **UPPERCASE**（`DAILY_CONVERSATION`…）——
/// 两条来源都要认，故先 `trim().toUpperCase()` 归一化再匹配。
///
/// 2026-10-07 修「首页卡片难度徽标恒为 CET6」：旧实现直接拿原串比对 UPPERCASE，
/// 服务端来的小写分类全部落到 `_` 默认分支 → 恒判 MEDIUM（LOW 文章显 CET6），
/// 且 [GetHomeArticlesUseCase] 的 `categoryToDifficulty(...) == userDifficulty`
/// 匹配集恒为空、"按难度过滤"退化成"全部显示"。
/// `ACADEMIC_EXCERPT` / `CLASSIC_NOVEL_EXCERPT` 是本地管道时代的旧名，服务端
/// 现在只产出 `academic_abstract`（HIGH）；三者都保留，存量行不被改动。
String categoryToDifficulty(String category) =>
    switch (category.trim().toUpperCase()) {
      'DAILY_CONVERSATION' || 'SCENE_DESCRIPTION' || 'SIMPLE_STORY' => 'LOW',
      'NEWS' || 'EXPOSITORY' || 'ARGUMENTATIVE' || 'PERSONAL_ESSAY' => 'MEDIUM',
      'ACADEMIC_ABSTRACT' ||
      'ACADEMIC_EXCERPT' ||
      'DEBATE_SPEECH' ||
      'LEGAL_DOCUMENT' ||
      'ART_CRITICISM' ||
      'CLASSIC_NOVEL_EXCERPT' =>
        'HIGH',
      // 未知分类兜底 MEDIUM：宁可徽标显示 CET6，也不要把文章判成别的难度——
      // 调用方（首页过滤）在不匹配时会退回"全部文章"，不会因此丢内容。
      _ => 'MEDIUM',
    };
