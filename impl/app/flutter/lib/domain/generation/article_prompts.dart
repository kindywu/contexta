/// 内容分类 → 难度映射（对照 Kotlin ArticlePrompts.kt 的 categoryToDifficulty）。
///
/// 2026-08-13（计划 B Task 6）：本地文章生成管道移除，本文件只保留
/// categoryToDifficulty（首页/查词链路按分类映射难度）；
/// buildArticleSystemPrompt/buildArticleUserPrompt/parseArticleLlmResponse
/// 与文章生成 prompt 模板一并删除。
/// 2026-08-14（计划 B Task 7）：查词远程化，word_prompts.dart 一并删除。
String categoryToDifficulty(String category) => switch (category) {
      'DAILY_CONVERSATION' || 'SCENE_DESCRIPTION' || 'SIMPLE_STORY' => 'LOW',
      'NEWS' ||
      'EXPOSITORY' ||
      'ARGUMENTATIVE' ||
      'PERSONAL_ESSAY' =>
        'MEDIUM',
      'ACADEMIC_EXCERPT' ||
      'DEBATE_SPEECH' ||
      'LEGAL_DOCUMENT' ||
      'ART_CRITICISM' ||
      'CLASSIC_NOVEL_EXCERPT' =>
        'HIGH',
      _ => 'MEDIUM',
    };
