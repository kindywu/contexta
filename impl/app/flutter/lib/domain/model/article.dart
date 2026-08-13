/// 文章领域模型（对齐 Kotlin Article.kt；2026-08-13 计划 B Task 6 移除
/// 本地生成管道后删去生成状态机字段 generationStartedAt/generationCompletedAt/
/// retryCount/lastRetryAt/maxRetries/nextRetryAt）。
class Article {
  final int id;
  final int batchId;
  final int orderIndex;
  final String contentCategory;
  final String? title;
  final ArticleStatus status;
  final int accumulatedReadSeconds;
  final String? readCompletedAt;
  final List<ArticleParagraph> paragraphs;

  const Article({
    required this.id,
    required this.batchId,
    required this.orderIndex,
    required this.contentCategory,
    required this.title,
    required this.status,
    required this.accumulatedReadSeconds,
    required this.readCompletedAt,
    this.paragraphs = const [],
  });

  /// 与 Kotlin data class 的 toString 语义一致。
  @override
  String toString() => 'Article(id=$id, batchId=$batchId, orderIndex=$orderIndex, '
      'contentCategory=$contentCategory, title=$title, status=$status, '
      'accumulatedReadSeconds=$accumulatedReadSeconds, '
      'readCompletedAt=$readCompletedAt, paragraphs=$paragraphs)';
}

/// 文章生成状态（存储层用大写枚举名 TEXT，如 'TIMEOUT'）。
enum ArticleStatus {
  pending('PENDING'),
  generating('GENERATING'),
  success('SUCCESS'),
  timeout('TIMEOUT'),
  failed('FAILED'),
  fatal('FATAL');

  const ArticleStatus(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => dbValue;

  static ArticleStatus fromDbValue(String value) {
    for (final s in values) {
      if (s.dbValue == value) return s;
    }
    throw ArgumentError('Unknown ArticleStatus: $value');
  }

  @override
  String toString() => dbValue;
}

/// 文章段落（对齐 Kotlin ArticleParagraph）。
class ArticleParagraph {
  /// DB 主键（来自 article_paragraph.id），0 表示未持久化或测试数据。
  final int id;
  final int orderIndex;
  final String englishText;
  final String chineseTranslation;

  const ArticleParagraph({
    this.id = 0,
    required this.orderIndex,
    required this.englishText,
    required this.chineseTranslation,
  });

  @override
  String toString() => 'ArticleParagraph(id=$id, orderIndex=$orderIndex, '
      'englishText=$englishText, chineseTranslation=$chineseTranslation)';
}

/// 文章内容类别全集（12 类，来源于 Android 端 ArticlePrompts.kt 的
/// categoryGuideline 映射与种子数据；原版以 String 存储，此处提供
/// 类型安全的枚举供 UI / 生成管道使用）。
enum ContentCategory {
  dailyConversation('DAILY_CONVERSATION'),
  sceneDescription('SCENE_DESCRIPTION'),
  simpleStory('SIMPLE_STORY'),
  news('NEWS'),
  expository('EXPOSITORY'),
  argumentative('ARGUMENTATIVE'),
  personalEssay('PERSONAL_ESSAY'),
  academicExcerpt('ACADEMIC_EXCERPT'),
  debateSpeech('DEBATE_SPEECH'),
  legalDocument('LEGAL_DOCUMENT'),
  artCriticism('ART_CRITICISM'),
  classicNovelExcerpt('CLASSIC_NOVEL_EXCERPT');

  const ContentCategory(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => dbValue;

  static ContentCategory fromDbValue(String value) {
    for (final c in values) {
      if (c.dbValue == value) return c;
    }
    throw ArgumentError('Unknown ContentCategory: $value');
  }

  @override
  String toString() => dbValue;
}
