import 'package:contexta/data/remote/dto/article_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArticleDeliveryDto.fromJson', () {
    test('delivery_date + articles 嵌套解析', () {
      final dto = ArticleDeliveryDto.fromJson({
        'delivery_date': '2026-09-03',
        'articles': [
          {
            'id': 42,
            'target_date': '2026-09-02',
            'difficulty': 'LOW',
            'content_category': 'news',
            'order_index': 1,
            'title': '标题',
            'status': 'SUCCESS',
            'regenerate_count': 0,
            'paragraphs': [
              {'order_index': 1, 'english_text': 'Hello', 'chinese_translation': '你好'},
            ],
          },
        ],
      });
      expect(dto.deliveryDate, '2026-09-03');
      expect(dto.articles, hasLength(1));
      expect(dto.articles.single.id, 42);
      expect(dto.articles.single.orderIndex, 1);
      expect(dto.articles.single.paragraphs.single.englishText, 'Hello');
    });

    test('articles 缺失/空 → 空列表（防御）', () {
      final dto = ArticleDeliveryDto.fromJson({'delivery_date': '2026-09-03'});
      expect(dto.articles, isEmpty);
    });
  });
}
