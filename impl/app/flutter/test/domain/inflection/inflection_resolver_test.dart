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
    ('cows', 'cow', InflectionType.sForm), // ws 结尾不进例外正则
    ('shows', 'show', InflectionType.sForm), // ws 结尾不进例外正则
    // 复数 -es
    ('boxes', 'box', InflectionType.sForm),
    ('churches', 'church', InflectionType.sForm),
    ('caches', 'cache', InflectionType.sForm),
    ('quizzes', 'quiz', InflectionType.sForm), // 双写还原
    // -es 段 +e 还原先行（first-hit 序修正，锁 uses→us 类遮蔽：实测 asset 库
    // 运行时首个命中必须是 use/write/bite/ride 而非 us/writ/bit/rid）
    ('uses', 'use', InflectionType.sForm),
    ('writes', 'write', InflectionType.sForm),
    ('bites', 'bite', InflectionType.sForm),
    ('rides', 'ride', InflectionType.sForm),
    // 反方向遮蔽例外表（base 正确但 base+e 是库内不同真词：passes→passe、
    // crosses→crosse，+e 先行会遮蔽，_exceptions 兜底）
    ('passes', 'pass', InflectionType.sForm),
    ('crosses', 'cross', InflectionType.sForm),
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
    ('died', 'die', InflectionType.pastTense), // ied 去 d
    ('tied', 'tie', InflectionType.pastTense), // ied 去 d
    // 现在分词
    ('going', 'go', InflectionType.presentParticiple),
    ('making', 'make', InflectionType.presentParticiple), // +e 还原
    ('running', 'run', InflectionType.presentParticiple), // 双写还原
    ('crying', 'cry', InflectionType.presentParticiple), // ing→y 还原
    ('dying', 'die', InflectionType.presentParticiple), // ying→ie 还原
    // 比较级 / 最高级
    ('bigger', 'big', InflectionType.comparative), // 双写还原
    ('happier', 'happy', InflectionType.comparative), // ier→y
    ('larger', 'large', InflectionType.comparative), // +e 还原
    ('biggest', 'big', InflectionType.superlative),
    ('happiest', 'happy', InflectionType.superlative),
    ('nicest', 'nice', InflectionType.superlative), // +e 还原
    // 实测驱动新增：希腊 -is→-es 复数（es 段 base+is 候选）
    ('analyses', 'analysis', InflectionType.sForm),
    ('crises', 'crisis', InflectionType.sForm),
    ('theses', 'thesis', InflectionType.sForm),
    ('hypotheses', 'hypothesis', InflectionType.sForm),
    ('bases', 'basis', InflectionType.sForm), // base 候选仍在，basis 兜底
    ('axes', 'axis', InflectionType.sForm),
    ('synopses', 'synopsis', InflectionType.sForm),
    ('praxes', 'praxis', InflectionType.sForm),
    // 拉丁 -ex/-ix→-ices（ices 段 stem+ex/ix 候选）
    ('indices', 'index', InflectionType.sForm),
    ('matrices', 'matrix', InflectionType.sForm),
    ('vertices', 'vertex', InflectionType.sForm),
    ('appendices', 'appendix', InflectionType.sForm),
    ('apices', 'apex', InflectionType.sForm),
    ('codices', 'codex', InflectionType.sForm),
    ('vortices', 'vortex', InflectionType.sForm),
    ('latices', 'latex', InflectionType.sForm),
    ('simplices', 'simplex', InflectionType.sForm),
    // 拉丁 -nx→-nges（ng 段 g→x 候选）
    ('larynges', 'larynx', InflectionType.sForm),
    ('pharynges', 'pharynx', InflectionType.sForm),
    ('salpinges', 'salpinx', InflectionType.sForm),
    // -ves→-vis
    ('pelves', 'pelvis', InflectionType.sForm),
    // -men→-man 复合词
    ('airmen', 'airman', InflectionType.sForm),
    ('women', 'woman', InflectionType.sForm),
    ('men', 'man', InflectionType.sForm), // 特例：守卫外直接生成
    ('gentlemen', 'gentleman', InflectionType.sForm),
    ('firemen', 'fireman', InflectionType.sForm),
    ('policemen', 'policeman', InflectionType.sForm),
    // -nies→-ney
    ('monies', 'money', InflectionType.sForm),
    // ied 直接去 ed
    ('alibied', 'alibi', InflectionType.pastTense),
    ('skied', 'ski', InflectionType.pastTense),
    // -ck→-c 还原
    ('panicked', 'panic', InflectionType.pastTense),
    ('arcked', 'arc', InflectionType.pastTense),
    ('panicking', 'panic', InflectionType.presentParticiple),
    // 入口小写（句首词 / 大写词形）
    ('Homes', 'home', InflectionType.sForm),
    ('Amalgamated', 'amalgamate', InflectionType.pastTense),
    ('Running', 'run', InflectionType.presentParticiple),
    // 例外表（实测驱动硬编码）
    ('children', 'child', InflectionType.sForm),
    ('data', 'datum', InflectionType.sForm),
    ('phenomena', 'phenomenon', InflectionType.sForm),
    ('criteria', 'criterion', InflectionType.sForm),
    ('media', 'medium', InflectionType.sForm),
    ('bacteria', 'bacterium', InflectionType.sForm),
    ('cacti', 'cactus', InflectionType.sForm),
    ('nuclei', 'nucleus', InflectionType.sForm),
    ('feet', 'foot', InflectionType.sForm),
    ('teeth', 'tooth', InflectionType.sForm),
    ('geese', 'goose', InflectionType.sForm),
    ('oxen', 'ox', InflectionType.sForm),
    ('chapeaux', 'chapeau', InflectionType.sForm),
    ('formulae', 'formula', InflectionType.sForm),
    ('staves', 'staff', InflectionType.sForm),
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
    'her', 'per', 'always', 'its', // 例外词表（her→h/he、per→p 经 er 分支误判；its 所有格→it 误判）
    'home', // 本身是词元形式，无变化
  ];

  for (final input in noCandidates) {
    test('$input 无候选', () {
      expect(resolver.resolveCandidates(input), isEmpty);
    });
  }

  /// -men→-man 守卫：非复合词不生成 man 候选。
  /// omen/amen 4 字词被词长守卫拦下（omen→oman 的 Oman 在库）；
  /// 孪生真词黑名单（词库全量核对，见 resolver 头部注释）：germen→german、
  /// somen→soman、humen→human、yumen→yuman 的孪生均在库，carmen→carman
  /// 防御性保留——已在例外词表入口早退，无任何候选。
  /// 注：specimen/abdomen/lumen 等残余词干生成的 speciman/abdoman/luman 噪声
  /// 候选不在词库，由仓储层查库滤除（守卫方案 B 的既定机制，见 resolver 注释）；
  /// numen/omen/amen/hymen 等在词库，精确命中先行，到不了解析器。
  group('-men→-man 守卫', () {
    test('omen 不生成 oman（词长守卫）', () {
      final candidates = resolver.resolveCandidates('omen');
      expect(candidates.where((c) => c.lemma == 'oman'), isEmpty,
          reason: '候选：${candidates.map((c) => '${c.lemma}:${c.type.name}').toList()}');
    });
    test('amen 不生成 aman（词长守卫）', () {
      final candidates = resolver.resolveCandidates('amen');
      expect(candidates.where((c) => c.lemma == 'aman'), isEmpty,
          reason: '候选：${candidates.map((c) => '${c.lemma}:${c.type.name}').toList()}');
    });
    test('carmen 无候选（早退）', () {
      expect(resolver.resolveCandidates('carmen'), isEmpty);
    });
    test('germen 无候选（早退，孪生 german 在库）', () {
      expect(resolver.resolveCandidates('germen'), isEmpty);
    });
    test('somen 无候选（早退，日语借词，孪生 soman 在库）', () {
      expect(resolver.resolveCandidates('somen'), isEmpty);
    });
    test('humen 无候选（早退，Humen 虎门，孪生 human 在库）', () {
      expect(resolver.resolveCandidates('humen'), isEmpty);
    });
    test('yumen 无候选（早退，Yumen 玉门，孪生 yuman 在库）', () {
      expect(resolver.resolveCandidates('yumen'), isEmpty);
    });
  });
}
