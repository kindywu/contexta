/// 种子数据 JSON 的解析模型。
///
/// 对照 Android 原版 seed/SeedArticle.kt（kotlinx.serialization）：
/// - SeedData(version, seedArticles)
/// - SeedArticle(difficultyLevel, contentCategory, orderIndex, title, paragraphs)
/// - SeedParagraph(orderIndex, englishText, chineseTranslation)
///
/// 使用手写 fromJson 而非 codegen：结构简单、仅种子文件一处使用，
/// 避免引入额外的序列化依赖。
library;

class SeedData {
  const SeedData({required this.version, required this.seedArticles});

  factory SeedData.fromJson(Map<String, dynamic> json) => SeedData(
        version: json['version'] as int,
        seedArticles: [
          for (final a in json['seedArticles'] as List)
            SeedArticle.fromJson(a as Map<String, dynamic>),
        ],
      );

  final int version;
  final List<SeedArticle> seedArticles;
}

class SeedArticle {
  const SeedArticle({
    required this.difficultyLevel,
    required this.contentCategory,
    required this.orderIndex,
    required this.title,
    required this.paragraphs,
  });

  factory SeedArticle.fromJson(Map<String, dynamic> json) => SeedArticle(
        difficultyLevel: json['difficultyLevel'] as String,
        contentCategory: json['contentCategory'] as String,
        orderIndex: json['orderIndex'] as int,
        title: json['title'] as String,
        paragraphs: [
          for (final p in json['paragraphs'] as List)
            SeedParagraph.fromJson(p as Map<String, dynamic>),
        ],
      );

  /// 与 Kotlin 相同：批次按难度分组（LOW / MEDIUM / HIGH）
  final String difficultyLevel;
  final String contentCategory;
  final int orderIndex;
  final String title;
  final List<SeedParagraph> paragraphs;
}

class SeedParagraph {
  const SeedParagraph({
    required this.orderIndex,
    required this.englishText,
    required this.chineseTranslation,
  });

  factory SeedParagraph.fromJson(Map<String, dynamic> json) => SeedParagraph(
        orderIndex: json['orderIndex'] as int,
        englishText: json['englishText'] as String,
        chineseTranslation: json['chineseTranslation'] as String,
      );

  final int orderIndex;
  final String englishText;
  final String chineseTranslation;
}
