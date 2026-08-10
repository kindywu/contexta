import 'package:contexta/domain/model/article.dart';
import 'package:contexta/domain/usecase/get_home_articles_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Kotlin GetHomeArticlesUseCase 语义的过滤/排序测试
/// （Kotlin 端无单独测试文件，按实现语义新写）。

Article _article(int id, {String category = 'NEWS', ArticleStatus? status, int? order}) =>
    Article(
      id: id,
      batchId: 9,
      orderIndex: order ?? id,
      contentCategory: category,
      title: null,
      status: status ?? ArticleStatus.success,
      generationStartedAt: null,
      generationCompletedAt: null,
      retryCount: 0,
      accumulatedReadSeconds: 0,
      readCompletedAt: null,
      lastRetryAt: null,
    );

void main() {
  final useCase = GetHomeArticlesUseCase();

  test('按难度过滤 排除 PENDING 并按 orderIndex 排序', () {
    final articles = [
      _article(1, category: 'NEWS', order: 3),
      _article(2, category: 'PERSONAL_ESSAY', order: 1),
      _article(3, category: 'EXPOSITORY', order: 2),
      _article(4, category: 'NEWS', status: ArticleStatus.pending, order: 4),
    ];

    final result = useCase(articles, 'MEDIUM', 5);

    expect(result.map((a) => a.id).toList(), [2, 3, 1]);
  });

  test('displayLimit 截断', () {
    final articles = [
      _article(1, category: 'NEWS', order: 2),
      _article(2, category: 'NEWS', order: 1),
      _article(3, category: 'NEWS', order: 3),
    ];

    final result = useCase(articles, 'MEDIUM', 2);

    expect(result.map((a) => a.id).toList(), [2, 1]);
  });

  test('难度匹配不足时回退全部已生成文章', () {
    final articles = [
      _article(1, category: 'NEWS'),
      _article(2, category: 'DAILY_CONVERSATION'),
      _article(3, category: 'SIMPLE_STORY'),
    ];

    // userDifficulty = HIGH，无匹配 → 返回全部非 PENDING（按序）
    final result = useCase(articles, 'HIGH', 5);

    expect(result.length, 3);
  });

  test('LOW 分类匹配 LOW 难度', () {
    final articles = [
      _article(1, category: 'DAILY_CONVERSATION'),
      _article(2, category: 'NEWS'),
    ];

    final result = useCase(articles, 'LOW', 5);

    expect(result.map((a) => a.id).toList(), [1]);
  });

  test('回退列表同样受 displayLimit 限制且排除 PENDING', () {
    final articles = [
      _article(1, category: 'NEWS'),
      _article(2, category: 'NEWS'),
      _article(3, category: 'NEWS', status: ArticleStatus.pending),
    ];

    final result = useCase(articles, 'LOW', 2);

    expect(result.map((a) => a.id).toList(), [1, 2]);
  });
}
