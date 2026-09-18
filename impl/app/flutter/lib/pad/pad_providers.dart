import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../domain/model/article.dart';

/// 单篇文章详情（含段落）——**首页 Hero 卡专用**。
///
/// 首页列表查询（`watchByBatch`）只查 `article` 表、不带段落；而 Hero 卡要
/// 显示文章开头段，让读者凭真实正文决定读不读（产品原则「语境优先」）。
/// 这里为"当前推荐的那一篇"单独取一次详情：一篇的额外查询，不值得把它并进
/// 首页的批量查询——那会加重**手机侧**的数据路径，而手机界面根本不用这段文字。
final padArticleDetailProvider = FutureProvider.family<Article?, int>((
  ref,
  articleId,
) {
  return ref.watch(articleRepositoryProvider).getArticle(articleId);
});
