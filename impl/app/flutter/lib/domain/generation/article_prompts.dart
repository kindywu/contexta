import '../model/article.dart';
import 'prompt_loader.dart';

/// 内容分类 → 难度映射（对照 Kotlin ArticlePrompts.kt 的 categoryToDifficulty）。
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

/// 文章生成 system prompt（对照 Kotlin buildArticleSystemPrompt）。
///
/// 加载 article_system.txt 的 COMMON + <难度> 节。
/// 占位符 {{title}} 保留为 LLM 填写的标题。
///
/// [difficulty] 为 "LOW"/"MEDIUM"/"HIGH"；null 时只返回 COMMON 节。
Future<String> buildArticleSystemPrompt([String? difficulty]) async {
  // Kotlin: listOfNotNull("COMMON", difficulty) → COMMON 在前，难度在后
  final ordered = ['COMMON', ?difficulty];
  return PromptLoader().loadSection(
    'article_system.txt',
    ordered,
    params: const {'title': 'The Article Title'},
    fallback: _articleSystemFallback,
  );
}

/// 文章生成 user prompt（对照 Kotlin buildArticleUserPrompt）。
///
/// 以 article_system.txt 的 USER_PROMPT 节为基础，追加分类指南。
Future<String> buildArticleUserPrompt(String category, int orderIndex) async {
  final basePrompt = await PromptLoader().loadSection(
    'article_system.txt',
    const ['USER_PROMPT'],
    params: {'orderIndex': '$orderIndex', 'category': category},
    fallback: 'Create article #$orderIndex in the category: $category',
  );

  final guideline = _categoryGuideline(category);
  if (guideline == null) return basePrompt;
  return '$basePrompt\n\nGuidelines for $category:\n$guideline';
}

String? _categoryGuideline(String category) => switch (category) {
      'DAILY_CONVERSATION' =>
        'A natural everyday dialogue or scenario between two people.',
      'SCENE_DESCRIPTION' =>
        'A vivid description of a place, event, or moment.',
      'SIMPLE_STORY' => 'A short narrative with a clear beginning and end.',
      'NEWS' => 'A brief news-style report on a current or hypothetical event.',
      'EXPOSITORY' => 'An explanatory piece that teaches a concept.',
      'ARGUMENTATIVE' => 'A short argument for or against a position.',
      'PERSONAL_ESSAY' => 'A reflective first-person piece on an experience.',
      'ACADEMIC_EXCERPT' =>
        'A scholarly excerpt suitable for advanced readers.',
      'DEBATE_SPEECH' => 'A persuasive speech or debate opening statement.',
      'LEGAL_DOCUMENT' => 'A simplified legal clause or contract excerpt.',
      'ART_CRITICISM' => 'An analytical piece about an artwork or performance.',
      'CLASSIC_NOVEL_EXCERPT' =>
        'An excerpt in the style of classic English literature.',
      _ => null,
    };

/// 解析 LLM 响应的 XML 格式：
/// `<title>...</title>` / `<paragraph>...</paragraph>` / `<translation>...</translation>`
/// 返回 (title, paragraphs)（对照 Kotlin parseArticleLlmResponse）。
({String title, List<ArticleParagraph> paragraphs}) parseArticleLlmResponse(
    String content) {
  final title = RegExp(r'<title>([\s\S]*?)</title>')
          .firstMatch(content)
          ?.group(1)
          ?.trim() ??
      'Untitled';

  final paragraphRegex = RegExp(r'<paragraph>([\s\S]*?)</paragraph>');
  final translationRegex = RegExp(r'<translation>([\s\S]*?)</translation>');

  final paragraphs = [
    for (final m in paragraphRegex.allMatches(content)) m.group(1)!.trim()
  ];
  final translations = [
    for (final m in translationRegex.allMatches(content)) m.group(1)!.trim()
  ];

  final result = <ArticleParagraph>[
    for (var i = 0; i < paragraphs.length; i++)
      ArticleParagraph(
        orderIndex: i + 1,
        englishText: paragraphs[i],
        chineseTranslation: i < translations.length ? translations[i] : '',
      ),
  ];

  return (title: title, paragraphs: result);
}

const _articleSystemFallback = 'You are an English language learning content '
    'creator.\n'
    'You create articles for Chinese learners at various difficulty levels.\n'
    '\n'
    'Output format:\n'
    '<title>The Article Title</title>\n'
    '<paragraph>English sentence here.</paragraph>\n'
    '<translation>中文翻译。</translation>\n'
    '<paragraph>Next sentence.</paragraph>\n'
    '<translation>下一句翻译。</translation>\n'
    '\n'
    'Rules:\n'
    '- Each paragraph must be 1-3 sentences, not longer\n'
    '- Each <paragraph> must be immediately followed by <translation>\n'
    '- Title must be 2-8 words\n'
    '- Output only the XML — no explanations, no markdown';
