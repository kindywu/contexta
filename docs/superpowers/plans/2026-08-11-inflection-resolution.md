# 词形解析（Inflection Resolution）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击 "homes" 时解析到数据库里的 "home" 词条，避免无谓的 LLM 查词，弹窗显示原词 + 词形标注。

**Architecture:** 在 `WordRepositoryImpl.lookupWord` 的精确 miss 与 LLM fallback 之间插入一层运行时规则型词形解析器（纯 Dart，无第三方库）：精确 miss 后生成候选词元逐一查库，命中返回词条并附 `InflectionResult` 标注；`WordDetail` 加可选 `inflection` 字段，UI 词头显示原词 + 标注行。

**Tech Stack:** Flutter/Dart、drift（SQLite）、flutter_test。

**Spec:** `docs/superpowers/specs/2026-08-11-inflection-resolution-design.md`（commit `e3dbe6f`）

## Global Constraints

- 无第三方词形库（lemmatizer/stemmer），规则全部手写；无 DB/ETL 变更、无迁移
- 查词链顺序固定：LRU → DB 精确 → 词形解析 → LLM fallback
- 误判防护三层：精确匹配先行；候选必须真实存在于 DB 才接受；`-ss/-us/-is/-as` 结尾不去 s
- 标注文案格式：`"homes 是 home 的复数形式"`，`sForm` 按词元义项词性区分（仅名词→复数；仅动词→第三人称单数；都有→并列；无义项→复数）
- 正确性实测还原率阈值 ≥95%（stardict exchange 语料），未达标补硬编码例外表（30-50 条纯数据）
- 不触发 LLM 是验收目标：解析命中时必须返回 detail，调用方不感知差异（`WordDetail?` 签名不变）

---

### Task 1: 规则引擎（纯函数，TDD）

**Files:**
- Create: `lib/domain/inflection/inflection_resolver.dart`
- Test: `test/domain/inflection/inflection_resolver_test.dart`

**Interfaces:**
- Produces:
  - `enum InflectionType { sForm, pastTense, presentParticiple, comparative, superlative }`
  - `class InflectionCandidate { final String lemma; final InflectionType type; const InflectionCandidate(this.lemma, this.type); }`
  - `abstract interface class InflectionResolver { List<InflectionCandidate> resolveCandidates(String spelling); }`
  - `class RuleInflectionResolver implements InflectionResolver { const RuleInflectionResolver(); }` — 后缀规则表生成候选，纯函数无 IO
- Consumes: 无

- [ ] **Step 1: 写失败测试（表驱动）**

```dart
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
    'series', 'species', 'analysis', 'this', 'homes' == '' ? 'x' : 'a', // 单字符
    'home', // 本身是词元形式，无变化
  ];

  for (final input in noCandidates) {
    test('$input 无候选', () {
      expect(resolver.resolveCandidates(input), isEmpty);
    });
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd impl/app/flutter && flutter test test/domain/inflection/inflection_resolver_test.dart`
Expected: FAIL — `undefined class 'RuleInflectionResolver'` 等编译错误

- [ ] **Step 3: 实现规则引擎**

```dart
/// 运行时规则型词形解析器（纯函数，无 IO、无第三方依赖）。
///
/// 输入文章点选的词形（如 "homes"），生成候选词元（如 "home"）及其变化类型。
/// 只处理规则变化：不规则词（children、went、better）在词库中是独立词条，
/// 由精确匹配先行命中，到不了解析器。
///
/// 误判防护：候选生成保守（词尾例外表 + 长度下限），实际"是否接受"由
/// 仓储层的"候选必须存在于 DB"把关（见 WordRepositoryImpl._resolveInflection）。
library;

enum InflectionType { sForm, pastTense, presentParticiple, comparative, superlative }

/// 候选词元 + 变化类型。[sForm] 同时覆盖名词复数与动词第三人称单数
/// （boxes→box、plays→play），二者后缀规则相同，区分依赖词元义项词性
/// （标注文案在仓储层按 POS 生成）。
class InflectionCandidate {
  const InflectionCandidate(this.lemma, this.type);
  final String lemma;
  final InflectionType type;

  @override
  String toString() => '$lemma:${type.name}';
}

abstract interface class InflectionResolver {
  /// 生成候选词元列表（按规则顺序，调用方按序查库命中第一个）。
  List<InflectionCandidate> resolveCandidates(String spelling);
}

/// 规则实现：后缀剥离 + 拼写还原，每条规则生成多个候选（如 running →
/// [runn(双写还原), run]），由查库存在性筛选。
class RuleInflectionResolver implements InflectionResolver {
  const RuleInflectionResolver();

  /// -ss/-us/-is/-as 结尾不去 s（news、bus、series 例外）
  static final _sException = RegExp(r'(ss|us|is|as)$');
  static const _minLen = 3;

  @override
  List<InflectionCandidate> resolveCandidates(String spelling) {
    final out = <InflectionCandidate>[];
    void add(String lemma, InflectionType type) {
      if (lemma.length >= _minLen && lemma != spelling) {
        out.add(InflectionCandidate(lemma, type));
      }
    }

    // ── sForm：名词复数 / 动词第三人称单数 ──
    if (!_sException.hasMatch(spelling)) {
      if (spelling.endsWith('ies')) {
        add('${spelling.substring(0, spelling.length - 3)}y', InflectionType.sForm);
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm); // movies→movie
      } else if (spelling.endsWith('ves')) {
        add('${spelling.substring(0, spelling.length - 3)}f', InflectionType.sForm); // halves→half
        add('${spelling.substring(0, spelling.length - 3)}fe', InflectionType.sForm); // wives→wife
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm);
      } else if (spelling.endsWith('es')) {
        add(spelling.substring(0, spelling.length - 2), InflectionType.sForm); // boxes→box
        add('${spelling.substring(0, spelling.length - 2)}e', InflectionType.sForm); // caches→cache
        // 双写还原：quizzes→quizz→quiz
        add(_undouble(spelling.substring(0, spelling.length - 2)), InflectionType.sForm);
      } else if (spelling.endsWith('s')) {
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm);
      }
    }

    // ── pastTense：过去式 / 过去分词 ──
    if (spelling.endsWith('ied')) {
      add('${spelling.substring(0, spelling.length - 3)}y', InflectionType.pastTense); // studied→study
    } else if (spelling.endsWith('ed')) {
      final base = spelling.substring(0, spelling.length - 2);
      add(base, InflectionType.pastTense); // played→play
      add(_undouble(base), InflectionType.pastTense); // stopped→stop
      add('${base}e', InflectionType.pastTense); // iced→ice
    }

    // ── presentParticiple ──
    if (spelling.endsWith('ing')) {
      final base = spelling.substring(0, spelling.length - 3);
      add(base, InflectionType.presentParticiple); // going→go
      add(_undouble(base), InflectionType.presentParticiple); // running→run
      add('${base}e', InflectionType.presentParticiple); // making→make
      add('${base}y', InflectionType.presentParticiple); // crying→cry
    }

    // ── comparative / superlative ──
    if (spelling.endsWith('ier')) {
      add('${spelling.substring(0, spelling.length - 3)}y', InflectionType.comparative); // happier→happy
    } else if (spelling.endsWith('er')) {
      final base = spelling.substring(0, spelling.length - 2);
      add(base, InflectionType.comparative); // larger→large 候选 larg
      add(_undouble(base), InflectionType.comparative); // bigger→big
      add('${base}e', InflectionType.comparative); // larger→large
    }
    if (spelling.endsWith('iest')) {
      add('${spelling.substring(0, spelling.length - 4)}y', InflectionType.superlative); // happiest→happy
    } else if (spelling.endsWith('est')) {
      final base = spelling.substring(0, spelling.length - 3);
      add(base, InflectionType.superlative);
      add(_undouble(base), InflectionType.superlative); // biggest→big
      add('${base}e', InflectionType.superlative); // nicest→nice
    }

    return out;
  }

  /// 双写辅音还原：runn→run、stopp→stop、bigg→big、quizz→quiz。
  /// 仅当末双字母相同且为辅音时还原。
  static String _undouble(String s) {
    if (s.length < 3) return s;
    final last = s[s.length - 1];
    final prev = s[s.length - 2];
    if (last == prev && _isConsonant(last)) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  static bool _isConsonant(String c) => !'aeiou'.contains(c);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd impl/app/flutter && flutter test test/domain/inflection/inflection_resolver_test.dart`
Expected: PASS（所有 case）

- [ ] **Step 5: Commit**

```bash
git add lib/domain/inflection/inflection_resolver.dart test/domain/inflection/inflection_resolver_test.dart
git commit -m "feat(reading): 词形解析规则引擎（homes→home，纯 Dart 无依赖）"
```

---

### Task 2: WordDetail 模型扩展

**Files:**
- Modify: `lib/domain/model/word_detail.dart`（类体尾部加字段 + copyWith）
- Test: `test/domain/model/models_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `InflectionType`（`import '../../domain/inflection/inflection_resolver.dart'` 路径需按实际）
- Produces: `WordDetail.inflection: InflectionResult?`、`WordDetail.copyWith({InflectionResult? inflection})`
  - `class InflectionResult { final String lemma; final InflectionType type; final String note; const InflectionResult({required this.lemma, required this.type, required this.note}); }` — 定义在 `inflection_resolver.dart`（模型文件 import 它）

- [ ] **Step 1: 在 `inflection_resolver.dart` 追加 `InflectionResult`**

在 Task 1 的 `inflection_resolver.dart` 文件末尾追加（`InflectionResult` 是仓库层组装的结果对象，与纯规则引擎同文件）：

```dart
/// 词形解析结果（仓储层组装：候选命中词条后，按义项词性生成展示文案）。
class InflectionResult {
  const InflectionResult({
    required this.lemma,
    required this.type,
    required this.note,
  });

  /// 词元，如 "home"
  final String lemma;

  /// 变化类型，如 [InflectionType.sForm]
  final InflectionType type;

  /// 展示文案，如 "homes 是 home 的复数形式"
  final String note;
}
```

- [ ] **Step 2: 写失败测试（models_test.dart 追加 group）**

```dart
import 'package:contexta/domain/inflection/inflection_resolver.dart';

// 在 main() 里追加：
group('WordDetail.inflection（词形解析标注）', () {
  test('默认 null', () {
    final w = WordDetail(
      wordId: 1,
      spellingDisplay: 'home',
      phoneticIpa: null,
      primarySense: null,
      allSenses: const [],
    );
    expect(w.inflection, isNull);
  });

  test('copyWith 设置与保留', () {
    final w = WordDetail(
      wordId: 1,
      spellingDisplay: 'home',
      phoneticIpa: null,
      primarySense: null,
      allSenses: const [],
    );
    final result = const InflectionResult(
      lemma: 'home', type: InflectionType.sForm, note: 'homes 是 home 的复数形式');
    final withInflection = w.copyWith(inflection: result);
    expect(withInflection.inflection, same(result));
    expect(withInflection.copyWith().inflection, same(result)); // 保留
  });
});
```

（按 `models_test.dart` 现有 import 风格补 `import 'package:contexta/domain/inflection/inflection_resolver.dart';`）

- [ ] **Step 3: 跑测试确认失败**

Run: `cd impl/app/flutter && flutter test test/domain/model/models_test.dart`
Expected: FAIL — `WordDetail` 无 `inflection` 字段 / 无 `copyWith`

- [ ] **Step 4: 修改 `word_detail.dart`**

```dart
import '../inflection/inflection_resolver.dart';

// WordDetail 类：构造函数加
  final InflectionResult? inflection;

  const WordDetail({
    required this.wordId,
    required this.spellingDisplay,
    required this.phoneticIpa,
    required this.primarySense,
    required this.allSenses,
    this.isInVocabulary = false,
    this.vocabularyEntryId,
    this.inflection, // ← 新增
  });

  /// 词形解析标注（解析命中时非空）。仅展示用途，不参与业务逻辑。
  WordDetail copyWith({InflectionResult? inflection}) => WordDetail(
        wordId: wordId,
        spellingDisplay: spellingDisplay,
        phoneticIpa: phoneticIpa,
        primarySense: primarySense,
        allSenses: allSenses,
        isInVocabulary: isInVocabulary,
        vocabularyEntryId: vocabularyEntryId,
        inflection: inflection ?? this.inflection,
      );

  // toString 追加 inflection 字段
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd impl/app/flutter && flutter test test/domain/model/models_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/domain/inflection/inflection_resolver.dart lib/domain/model/word_detail.dart test/domain/model/models_test.dart
git commit -m "feat(reading): WordDetail 加 inflection 标注字段与 copyWith"
```

---

### Task 3: 仓储层集成（解析链 + POS 标注）

**Files:**
- Modify: `lib/data/repository/word_repository_impl.dart`
- Modify: `lib/di/providers.dart:110-118`（若需要；见 Step 4 说明）
- Test: `test/data/repository/repositories_test.dart`（追加 group）

**Interfaces:**
- Consumes: Task 1 `RuleInflectionResolver`、`InflectionCandidate`；Task 2 `InflectionResult`、`WordDetail.inflection`
- Produces:
  - `WordRepositoryImpl` 构造函数加可选参数 `InflectionResolver inflectionResolver = const RuleInflectionResolver()`（默认值 → 现有调用方与测试零改动）
  - 查词链：`lookupWord` 精确 miss 后调 `_resolveInflection(normalized)`；命中 → `_buildWordDetail` + POS 标注 + `copyWith` + 缓存（key=原词）→ 返回；`findLocal` 同样复用
  - 私有方法：`Future<(WordRow, InflectionCandidate)?> _resolveInflection(String normalized)`、`String _inflectionNote(String source, String lemma, InflectionType type, WordDetail detail)`

- [ ] **Step 1: 写失败测试（repositories_test.dart 追加 group）**

```dart
// 追加到 main() 内、现有 WordRepository group 之后：

group('WordRepository 词形解析（inflection resolution）', () {
  test('homes 精确 miss 时解析命中 home，不触发 LLM', () async {
    // 预置 home 词条（saveLlmResult 返回 WordDetail）
    await wordRepo.saveLlmResult(
      'home', '/hoʊm/', const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
            chineseMeaning: '家', englishDefinition: 'a place where you live',
            examples: const []),
      ],
    );
    var llmCalled = 0;
    final detail = await wordRepo.lookupWord('homes', (_) async {
      llmCalled++;
      return null;
    });
    expect(llmCalled, 0);
    expect(detail, isNotNull);
    expect(detail!.spellingDisplay, 'home');
    expect(detail.inflection, isNotNull);
    expect(detail.inflection!.lemma, 'home');
    expect(detail.inflection!.type, InflectionType.sForm);
    expect(detail.inflection!.note, 'homes 是 home 的复数形式'); // 仅名词义项
  });

  test('plays 解析命中 play，义项含名词+动词时标注并列', () async {
    await wordRepo.saveLlmResult(
      'play', '/pleɪ/', const [
        WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
            chineseMeaning: '戏剧', englishDefinition: 'a stage performance',
            examples: const []),
        WordSense(id: 0, orderIndex: 2, partOfSpeech: 'v.',
            chineseMeaning: '玩耍', englishDefinition: 'to do an activity',
            examples: const []),
      ],
    );
    final detail = await wordRepo.lookupWord('plays', (_) async => null);
    expect(detail, isNotNull);
    expect(detail!.inflection!.note, 'plays 是 play 的复数形式 / 第三人称单数');
  });

  test('解析命中结果进 LRU 缓存（key=原词，第二次零查询）', () async {
    await wordRepo.saveLlmResult('box', null, const [
      WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
          chineseMeaning: '盒子', englishDefinition: 'a container',
          examples: const []),
    ]);
    final first = await wordRepo.lookupWord('boxes', (_) async => null);
    expect(first, isNotNull);
    expect(first!.inflection, isNotNull);
    // 第二次：LLM 不触发即可（缓存命中无法直接观测，间接验证）
    final second = await wordRepo.lookupWord('boxes', (_) async {
      fail('第二次查询不应走到 LLM');
    });
    expect(second!.wordId, first.wordId);
  });

  test('全部候选 miss → 正常走 LLM（含标注为 null）', () async {
    var llmCalled = 0;
    final detail = await wordRepo.lookupWord('xyzzy', (_) async {
      llmCalled++;
      return null;
    });
    expect(llmCalled, 1);
    expect(detail, isNull); // LLM 失败 → null（现有语义）
  });

  test('findLocal 同样解析（手动加词入口行为一致）', () async {
    await wordRepo.saveLlmResult('wife', null, const [
      WordSense(id: 0, orderIndex: 1, partOfSpeech: 'n.',
          chineseMeaning: '妻子', englishDefinition: 'a married woman',
          examples: const []),
    ]);
    final detail = await wordRepo.findLocal('wives');
    expect(detail, isNotNull);
    expect(detail!.spellingDisplay, 'wife');
    expect(detail.inflection, isNotNull);
  });
});
```

需要补的 import：`package:contexta/domain/inflection/inflection_resolver.dart`

- [ ] **Step 2: 跑测试确认失败**

Run: `cd impl/app/flutter && flutter test test/data/repository/repositories_test.dart`
Expected: FAIL — 解析链未实现（homes 走到 LLM 或返回 null）

- [ ] **Step 3: 实现解析链**

`word_repository_impl.dart` 改动：

```dart
import '../../domain/inflection/inflection_resolver.dart';

// 构造：加可选参数（默认值保证现有调用零改动）
  WordRepositoryImpl(
    this._wordDao,
    this._wordSenseDao,
    this._exampleSentenceDao,
    this._vocabularyEntryDao, {
    InflectionResolver inflectionResolver = const RuleInflectionResolver(),
  }) : _inflectionResolver = inflectionResolver;

  final InflectionResolver _inflectionResolver;

// lookupWord 中，DB 精确 miss 之后、LLM 之前插入：
      final existing = await _wordDao.getByNormalized(normalized);
      if (existing != null) { ... 不变 ... }

      // 2.5 词形解析：精确 miss 后，规则引擎候选逐一查库
      final resolved = await _resolveInflection(normalized);
      if (resolved != null) {
        final (wordRow, candidate) = resolved;
        debugPrint('[WordRepo] INFLECTION HIT "$normalized" → ${candidate.lemma} '
            '(${candidate.type.name}) id=${wordRow.id}');
        final detail = await _buildWordDetail(wordRow);
        final withInflection = detail.copyWith(
          inflection: InflectionResult(
            lemma: candidate.lemma,
            type: candidate.type,
            note: _inflectionNote(
                normalized, candidate.lemma, candidate.type, detail),
          ),
        );
        _lruCache[normalized] = withInflection;
        return withInflection;
      }

      // 3. LLM fallback ...

// findLocal 同样插入（精确 miss 后）：
      final existing = await _wordDao.getByNormalized(normalized);
      if (existing == null) {
        final resolved = await _resolveInflection(normalized);
        if (resolved != null) {
          final (wordRow, candidate) = resolved;
          final detail = await _buildWordDetail(wordRow);
          final withInflection = detail.copyWith(
            inflection: InflectionResult(
              lemma: candidate.lemma,
              type: candidate.type,
              note: _inflectionNote(
                  normalized, candidate.lemma, candidate.type, detail),
            ),
          );
          _lruCache[normalized] = withInflection;
          return withInflection;
        }
        return null;
      }

// 新增私有方法：
  /// 词形解析：候选按序查库，返回第一个命中的 (词条行, 候选)。
  Future<(WordRow, InflectionCandidate)?> _resolveInflection(
      String normalized) async {
    for (final candidate in _inflectionResolver.resolveCandidates(normalized)) {
      final row = await _wordDao.getByNormalized(candidate.lemma);
      if (row != null) return (row, candidate);
    }
    return null;
  }

  /// 标注文案：sForm 按词元义项词性区分复数 / 第三人称单数。
  String _inflectionNote(
      String source, String lemma, InflectionType type, WordDetail detail) {
    switch (type) {
      case InflectionType.sForm:
        final pos = detail.allSenses.map((s) => s.partOfSpeech).toSet();
        final hasNoun = pos.any((p) => p.contains('n'));
        final hasVerb = pos.any((p) => p.contains('v'));
        if (hasNoun && hasVerb) return '$source 是 $lemma 的复数形式 / 第三人称单数';
        if (hasVerb) return '$source 是 $lemma 的第三人称单数形式';
        return '$source 是 $lemma 的复数形式';
      case InflectionType.pastTense:
        return '$source 是 $lemma 的过去式/过去分词';
      case InflectionType.presentParticiple:
        return '$source 是 $lemma 的现在分词';
      case InflectionType.comparative:
        return '$source 是 $lemma 的比较级';
      case InflectionType.superlative:
        return '$source 是 $lemma 的最高级';
    }
  }
```

注意：`saveLlmResult` 内部 `_buildWordDetail` 路径不变；`invalidateCache` 不变。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd impl/app/flutter && flutter test test/data/repository/repositories_test.dart`
Expected: PASS（含新增 group，且现有 3-tier 测试不受影响）

- [ ] **Step 5: 确认 providers 无需改动**

`providers.dart:110` 的 `WordRepositoryImpl(WordDao(db), ...)` 用默认参数 → 零改动。检查 `WordRepositoryImpl` 其余调用方（`grep -rn "WordRepositoryImpl(" lib test`），确认全部走默认参数。

- [ ] **Step 6: Commit**

```bash
git add lib/data/repository/word_repository_impl.dart test/data/repository/repositories_test.dart
git commit -m "feat(reading): 查词链插入词形解析（精确 miss 后，LLM 前，含 POS 标注）"
```

---

### Task 4: UI（词头原词 + 标注行）

**Files:**
- Modify: `lib/ui/reading/reading_controller.dart`（`WordSheetData` 类 + `_lookupWord`）
- Modify: `lib/ui/reading/reading_screen.dart`（`_WordSheetBody` 音标下方加标注行）

**Interfaces:**
- Consumes: Task 2 `WordDetail.inflection?.note`、Task 3 解析链
- Produces: `WordSheetData.inflectionNote: String?`

- [ ] **Step 1: `WordSheetData` 加字段**

`reading_controller.dart:137-178`：

```dart
  const WordSheetData({
    required this.word,
    this.isLoading = false,
    this.phonetic,
    this.senses = const [],
    this.isInVocabulary = false,
    this.wordId,
    this.vocabularyEntryId,
    this.inflectionNote, // ← 新增
  });

  final String? inflectionNote; // ← 新增：词形解析标注（"homes 是 home 的复数形式"）

  // copyWith 加参数（简单 nullable，无需 _unset：标注只设不置空）：
  WordSheetData copyWith({
    bool? isLoading,
    String? phonetic,
    List<WordSenseUi>? senses,
    bool? isInVocabulary,
    Object? wordId = _unset,
    Object? vocabularyEntryId = _unset,
    String? inflectionNote,
  }) =>
      WordSheetData(
        ...
        inflectionNote: inflectionNote ?? this.inflectionNote,
      );
```

- [ ] **Step 2: `_lookupWord` 词头用原词 + 传标注**

`reading_controller.dart:655-667` 成功分支：

```dart
    if (detail != null) {
      state = state.copyWith(
        wordSheetData: WordSheetData(
          // 解析命中显示原词（homes），精确命中显示词条 spellingDisplay（保持现状）
          word: detail.inflection == null ? detail.spellingDisplay : normalized,
          isLoading: false,
          phonetic: detail.phoneticIpa,
          senses: _groupSensesByPartOfSpeech(detail.allSenses),
          isInVocabulary: detail.isInVocabulary,
          wordId: detail.wordId,
          vocabularyEntryId: detail.vocabularyEntryId,
          inflectionNote: detail.inflection?.note,
        ),
        isWordSheetVisible: true,
      );
    }
```

- [ ] **Step 3: `_WordSheetBody` 加标注行**

`reading_screen.dart` 音标 `Text`（约 588-592 行）之后插入：

```dart
          if (data!.phonetic != null && !data!.isLoading)
            Text(
              data!.phonetic!,
              style: AppType.phonetic.copyWith(fontSize: 13),
            ),
          // 词形解析标注：homes 是 home 的复数形式
          if (data!.inflectionNote != null && !data!.isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                data!.inflectionNote!,
                style: AppType.textTheme.bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ),
```

- [ ] **Step 4: 编译与现有测试验证**

Run: `cd impl/app/flutter && flutter analyze && flutter test`
Expected: 无 analyze 错误；全部测试 PASS（含 Task 3 的解析 group）

- [ ] **Step 5: Commit**

```bash
git add lib/ui/reading/reading_controller.dart lib/ui/reading/reading_screen.dart
git commit -m "feat(reading): 查词弹窗显示原词词头 + 词形标注行"
```

---

### Task 5: 正确性实测（stardict exchange 语料）

**Files:**
- Create: `test/domain/inflection/accuracy_probe_test.dart`

**Interfaces:**
- Consumes: Task 1 `RuleInflectionResolver`
- Produces: 还原率报告 + 例外表决策依据（若 <95% 或发现系统性缺陷，在 Task 1 的 resolver 前加 `_exceptions` 硬编码映射，30-50 条）

- [ ] **Step 1: 写实测测试**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:contexta/domain/inflection/inflection_resolver.dart';

/// 正确性实测：从 stardict.db 的 exchange 字段抽取 (词形→词元, 类型) 语料，
/// 跑规则引擎还原率。语料仅测试期使用（impl/etl/ref/ 数据），不引入运行时依赖。
///
/// 还原率 <95% 时失败并打印 TOP 失败样本（按类型分组）——用于人工判断：
/// - 失败样本主要是不规则词（children→child，库内已有精确匹配，无害）→ 规则定稿
/// - 失败样本暴露系统性规则缺陷（如 analyses→analysis）→ 补硬编码例外表
void main() {
  final dbPath = '../../../../etl/ref/stardict.db'; // cwd = impl/app/flutter
  if (!File(dbPath).existsSync()) {
    // ref 数据缺失（如 CI 环境）时静默跳过
    return;
  }

  const resolver = RuleInflectionResolver();

  /// exchange 编码 → 我们的类型；s/3→sForm，p/d→pastTense，i→presentParticiple，j/r→比较/最高级
  InflectionType? mapType(String code) => switch (code) {
        's' || '3' => InflectionType.sForm,
        'p' || 'd' => InflectionType.pastTense,
        'i' => InflectionType.presentParticiple,
        'j' => InflectionType.comparative,
        'r' => InflectionType.superlative,
        _ => null,
      };

  test('stardict exchange 语料还原率 ≥95%', () {
    final db = sqlite3.open(dbPath);
    final rows = db.select(
        "SELECT word, exchange FROM stardict WHERE exchange LIKE '0:%/%' OR exchange LIKE '1:%/%'");

    // 抽取 (form, lemma, type)：兼容 0:lemma/1:type 与 1:type/0:lemma 两种顺序
    final pairs = <(String, String, InflectionType)>[];
    for (final row in rows) {
      final word = row['word'] as String;
      final exchange = row['exchange'] as String;
      String? lemma;
      String? codes;
      for (final part in exchange.split('/')) {
        if (part.startsWith('0:')) lemma = part.substring(2);
        if (part.startsWith('1:')) codes = part.substring(2);
      }
      if (lemma == null || codes == null || word == lemma) continue;
      // 只统计全字母词形（排除 'ands、.22 等非标准词）
      if (!RegExp(r"^[A-Za-z]{3,}$").hasMatch(word)) continue;
      if (!RegExp(r"^[A-Za-z]+$").hasMatch(lemma)) continue;
      for (final code in codes.split('')) {
        final type = mapType(code);
        if (type != null) pairs.add((word, lemma, type));
      }
    }
    db.dispose();

    final missed = <(String, String, InflectionType)>[];
    for (final (form, lemma, type) in pairs) {
      final candidates = resolver.resolveCandidates(form);
      final hit = candidates.any((c) => c.lemma == lemma && c.type == type);
      if (!hit) missed.add((form, lemma, type));
    }

    final rate = (pairs.length - missed.length) / pairs.length;
    // 按类型分组的失败样本（人工判读用）
    final byType = <InflectionType, List<(String, String)>>{};
    for (final (form, lemma, type) in missed) {
      byType.putIfAbsent(type, () => []).add((form, lemma));
    }
    for (final entry in byType.entries) {
      final sample = entry.value.take(20).map((p) => '${p.$1}→${p.$2}').join(', ');
      // ignore: avoid_print
      print('[${entry.key.name}] miss ${entry.value.length}: $sample');
    }

    expect(rate, greaterThanOrEqualTo(0.95),
        reason: '还原率 ${(rate * 100).toStringAsFixed(1)}% < 95%，'
            '总语料 ${pairs.length}，miss ${missed.length}。'
            '检查失败样本：若为系统性规则缺陷，补例外表（RuleInflectionResolver 加 _exceptions）。');
    // ignore: avoid_print
    print('还原率 ${(rate * 100).toStringAsFixed(1)}% '
        '（语料 ${pairs.length}，miss ${missed.length}）');
  });
}
```

- [ ] **Step 2: 跑实测**

Run: `cd impl/app/flutter && flutter test test/domain/inflection/accuracy_probe_test.dart`
Expected: 输出还原率数字与 miss 样本分组。

- [ ] **Step 3: 判定与决策（不写代码，先记录）**

- 还原率 ≥95% 且 miss 样本主要是**不规则词**（children→child、went→go 等，库内已有精确匹配）→ **规则定稿，无需例外表**，进入 Step 4 提交实测
- 还原率 <95% 或 miss 样本暴露**系统性规则缺陷**（如 `analyses→analysis` 成批）→ 按 spec 补硬编码例外表：

```dart
  /// 例外表：规则无法还原的词形（系统性缺陷时启用，纯数据无依赖）。
  /// 仅在正确性实测暴露缺陷时补充；目前为空。
  static const Map<String, String> _exceptions = {
    // 示例：'analyses': 'analysis',
  };

  // resolveCandidates 开头：
    final exceptionLemma = _exceptions[spelling];
    if (exceptionLemma != null) {
      out.add(InflectionCandidate(exceptionLemma, InflectionType.sForm));
    }
```

补例外表后重跑 Step 2，并回到 Task 1 的测试文件补充对应用例，直到通过。

- [ ] **Step 4: Commit（两种结局二选一）**

无例外表：

```bash
git add test/domain/inflection/accuracy_probe_test.dart
git commit -m "test(reading): stardict exchange 语料实测还原率（≥95% 阈值）"
```

有例外表：

```bash
git add lib/domain/inflection/inflection_resolver.dart test/domain/inflection/accuracy_probe_test.dart test/domain/inflection/inflection_resolver_test.dart
git commit -m "feat(reading): 词形解析例外表（实测驱动）+ 还原率实测"
```

---

### Task 6: 文档同步与收尾

**Files:**
- Modify: `impl/app/flutter/docs/database-schema.md` 或查词链路所在主题文档（git diff 判定）
- Modify: `docs/superpowers/specs/2026-08-11-inflection-resolution-design.md`（若实现偏离设计，同步修正）

- [ ] **Step 1: 全量验证**

Run: `cd impl/app/flutter && flutter analyze && flutter test`
Expected: 0 analyze 错误，全部测试 PASS

- [ ] **Step 2: 分析 git diff，同步主题文档**

按 CLAUDE.md「文档同步规则」：分析本次 diff，找到查词链路相关主题文档（`docs/database-schema.md` 或其他记录查词 3 层链路的文档），补充词形解析层的描述（组件、查词链第 2.5 层、标注语义、防误判机制）。若查词链路在现有文档中无专节，新增简短主题节或新文档（按 git diff 与现有文档结构判定）。

- [ ] **Step 3: 检查 temp_docs 无残留，提交**

```bash
git add -A
git commit -m "docs: 同步词形解析到主题文档（查词链路 2.5 层）"
```

（提交前确认 `docs/superpowers/` 下新文件的 `-f` 强制 add 约定，若文档在 gitignore 内）
