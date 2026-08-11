import 'package:flutter_test/flutter_test.dart';
import 'package:contexta/domain/inflection/inflection_resolver.dart';

void main() {
  const resolver = RuleInflectionResolver();

  /// (输入, 期望命中的词元, 期望类型) — 只断言"包含"，候选列表可含同词元多类型
  const cases = <(String, String, InflectionType)>[
    // 复数 -s
    ('homes', 'home', InflectionType.sForm),
    ('books', 'book', InflectionType.sForm),
    ('plays', 'play', InflectionType.sForm), // 也覆盖三单
    ('goes', 'go', InflectionType.sForm),
    // 复数 -es
    ('boxes', 'box', InflectionType.sForm),
    ('churches', 'church', InflectionType.sForm),
    ('caches', 'cache', InflectionType.sForm),
    ('quizzes', 'quiz', InflectionType.sForm), // 双写还原
    // 复数 -ies
    ('cities', 'city', InflectionType.sForm),
    ('movies', 'movie', InflectionType.sForm), // 去 s 而非 ies→y
    // 复数 -ves
    ('wives', 'wife', InflectionType.sForm),
    ('halves', 'half', InflectionType.sForm),
    // 过去式
    ('played', 'play', InflectionType.pastTense),
    ('stopped', 'stop', InflectionType.pastTense), // 双写还原
    ('iced', 'ice', InflectionType.pastTense), // +e 还原
    ('studied', 'study', InflectionType.pastTense), // ied→y
    // 现在分词
    ('going', 'go', InflectionType.presentParticiple),
    ('making', 'make', InflectionType.presentParticiple), // +e 还原
    ('running', 'run', InflectionType.presentParticiple), // 双写还原
    ('crying', 'cry', InflectionType.presentParticiple), // ing→y 还原
    // 比较级 / 最高级
    ('bigger', 'big', InflectionType.comparative), // 双写还原
    ('happier', 'happy', InflectionType.comparative), // ier→y
    ('larger', 'large', InflectionType.comparative), // +e 还原
    ('biggest', 'big', InflectionType.superlative),
    ('happiest', 'happy', InflectionType.superlative),
    ('nicest', 'nice', InflectionType.superlative), // +e 还原
  ];

  for (final (input, lemma, type) in cases) {
    test('$input → $lemma (${type.name})', () {
      final candidates = resolver.resolveCandidates(input);
      expect(
        candidates.where((c) => c.lemma == lemma && c.type == type),
        isNotEmpty,
        reason: '候选：${candidates.map((c) => '${c.lemma}:${c.type.name}').toList()}',
      );
    });
  }

  /// 不该生成任何候选（词尾例外 / 单字母 / 规则不适用）
  const noCandidates = <String>[
    'news', 'bus', 'gas', 'his', 'has', 'was', 'is', 'as', // -ss/-us/-is/-as 例外
    'series', 'species', 'analysis', 'this', 'a', // 单字符
    'home', // 本身是词元形式，无变化
  ];

  for (final input in noCandidates) {
    test('$input 无候选', () {
      expect(resolver.resolveCandidates(input), isEmpty);
    });
  }
}
