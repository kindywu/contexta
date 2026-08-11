/// 运行时规则型词形解析器（纯函数，无 IO、无第三方依赖）。
///
/// 输入文章点选的词形（如 "homes"），生成候选词元（如 "home"）及其变化类型。
/// 规则覆盖：复数/三单（-s/-es/-ies/-ves、希腊 -is→-es、拉丁 -ex/-ix/-x、
/// -men→-man 复合词）、过去式（-ed/-ied、-ck 双写）、现在分词（-ing）、
/// 比较级/最高级（-er/-ier/-est/-iest）。不规则动词（went、ate）在词库中
/// 是独立词条，由精确匹配先行命中，到不了解析器；高频拉丁/外来复数
/// （children→child、data→datum 等）由 [_exceptions] 硬编码表兜底
/// （由正确性实测驱动补充，见 test/domain/inflection/accuracy_probe_test.dart）。
///
/// 误判防护：候选生成保守（词尾例外表 + 长度下限），实际"是否接受"由
/// 仓储层的"候选必须存在于 DB"把关（见 WordRepositoryImpl._resolveInflection）。
/// 生成的候选可能含噪声（如 changes→changx），无害——查库存在性会过滤。
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

  /// -ss/-us/-is/-as 结尾不去 s（bus、gas、his、analysis 例外）。
  static final _sException = RegExp(r'(ss|us|is|as)$');

  /// 本身是词元的例外词（入口早退，任何段都不解析）：
  /// - "news" 是 mass noun 非复数；ws 结尾不能整体进正则——cows→cow、
  ///   shows→show 是合法复数规则；
  /// - "series"/"species" 单复数同形（拉丁借词），纯后缀规则无法区分
  ///   cities→city 与 series（剥 ies/es 后 "ser" 与 "cit" 结构相同），只能显式例外；
  /// - "her"/"per" 会经 comparative 的 er 分支误生成 h/he/p（元素符号，均在库）；
  /// - "always" 以 s 结尾的非复数实词，会误生成 alway；
  /// - -men→-man 分支的孪生真词黑名单（词库全量扫描核对）：以下真实词形
  ///   不在词库（点选进 resolver），其 -man 孪生是库内不同真词，查库滤除失效：
  ///   "germen"→german、 "somen"（日语借词素面）→soman、 "humen"（虎门）
  ///   →human、 "yumen"（玉门）→yuman；"carmen"→carman 防御性保留
  ///   （carman 当前不在库）。罕见词，精确 miss 走 LLM 兜底。
  static const _sExceptionWords = {
    'news', 'series', 'species', 'her', 'per', 'always',
    'carmen', 'germen', 'somen', 'humen', 'yumen',
  };
  static const _minLen = 3;

  /// 例外表：规则无法还原的高频拉丁/外来复数（实测驱动，纯数据无依赖）。
  /// stardict exchange 语料实测（accuracy_probe_test）还原率 99.4%，
  /// 残余 miss 均为不规则动词/生僻外来复数，规则与例外表到此定稿。
  static const Map<String, String> _exceptions = {
    // 核心不规则复数（词库中多为独立词条，此处保证无网络兜底）
    'children': 'child',
    'brethren': 'brother',
    'oxen': 'ox',
    'geese': 'goose',
    'mice': 'mouse',
    'feet': 'foot',
    'teeth': 'tooth',
    'cherubim': 'cherub',
    // 拉丁 2 变格 -um→-a
    'data': 'datum',
    'phenomena': 'phenomenon',
    'criteria': 'criterion',
    'media': 'medium',
    'bacteria': 'bacterium',
    'strata': 'stratum',
    'curricula': 'curriculum',
    'memoranda': 'memorandum',
    'genera': 'genus',
    'spectra': 'spectrum',
    'aquaria': 'aquarium',
    'compendia': 'compendium',
    'crematoria': 'crematorium',
    'charismata': 'charisma',
    'schemata': 'schema',
    // 拉丁 1 变格 -a→-ae
    'formulae': 'formula',
    'vertebrae': 'vertebra',
    'larvae': 'larva',
    'algae': 'alga',
    'alumnae': 'alumna',
    'amoebae': 'amoeba',
    'minutiae': 'minutia',
    'abscissae': 'abscissa',
    'cannulae': 'cannula',
    // 拉丁/意大利 -us/-o→-i
    'cacti': 'cactus',
    'nuclei': 'nucleus',
    'radii': 'radius',
    'stimuli': 'stimulus',
    'fungi': 'fungus',
    'syllabi': 'syllabus',
    'cocci': 'coccus',
    // 法语 -eau→-eaux
    'chapeaux': 'chapeau',
    'bureaux': 'bureau',
    'bandeaux': 'bandeau',
    'cadeaux': 'cadeau',
    'bateaux': 'bateau',
    'tableaux': 'tableau',
    // 其他
    'staves': 'staff',
    'clitorides': 'clitoris',
  };

  @override
  List<InflectionCandidate> resolveCandidates(String spelling) {
    // 入口小写：生产链路 normalize 已小写（WordRepository.normalize），此处兜底
    // 大写词形（句首词 Homes→home、语料中的 Amalgamated→amalgamate）
    spelling = spelling.toLowerCase();
    // 例外词本身是词元，任何段都不解析——her/per 的误判路径在 comparative
    // 的 er 分支（her→h/he、per→p），必须在入口早退而非仅拦 sForm 段
    if (_sExceptionWords.contains(spelling)) {
      return const [];
    }
    final out = <InflectionCandidate>[];
    // 例外表放最前：data→datum 等规则无法还原，直接给出词元（sForm 语义）
    final exceptionLemma = _exceptions[spelling];
    if (exceptionLemma != null) {
      out.add(InflectionCandidate(exceptionLemma, InflectionType.sForm));
    }
    void add(String lemma, InflectionType type) {
      // 长度下限作用于输入拼写（保护 "a" 等单字符），而非词元——go→goes、
      // go→going 的词元只有 2 个字符，同样合法
      if (spelling.length >= _minLen && lemma != spelling) {
        out.add(InflectionCandidate(lemma, type));
      }
    }

    // ── sForm：名词复数 / 动词第三人称单数 ──
    if (!_sException.hasMatch(spelling)) {
      if (spelling.endsWith('ies')) {
        add('${spelling.substring(0, spelling.length - 3)}y', InflectionType.sForm);
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm); // movies→movie
        // -nies→-ney：monies→money、euromonies→euromoney（先行的 y/去 s 候选优先命中）
        add('${spelling.substring(0, spelling.length - 3)}ey', InflectionType.sForm);
      } else if (spelling.endsWith('ves')) {
        add('${spelling.substring(0, spelling.length - 3)}f', InflectionType.sForm); // halves→half
        add('${spelling.substring(0, spelling.length - 3)}fe', InflectionType.sForm); // wives→wife
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm);
        // -ves→-vis：pelves→pelvis（拉丁 -is 复数，同 es 段 base+is）
        add('${spelling.substring(0, spelling.length - 2)}is', InflectionType.sForm);
      } else if (spelling.endsWith('es')) {
        final base = spelling.substring(0, spelling.length - 2);
        add(base, InflectionType.sForm); // boxes→box
        add('${base}e', InflectionType.sForm); // caches→cache
        // 双写还原：quizzes→quizz→quiz
        add(_undouble(base), InflectionType.sForm);
        // 希腊 -is→-es：analyses→analysis、crises→crisis、bases→basis
        // （噪声候选如 boxis 被查库过滤；bases 的 base 候选先行命中）
        add('${base}is', InflectionType.sForm);
        // 拉丁 -ex/-ix→-ices：indices→index、matrices→matrix、appendices→appendix
        if (base.endsWith('ic')) {
          final stem = base.substring(0, base.length - 2);
          add('${stem}ex', InflectionType.sForm);
          add('${stem}ix', InflectionType.sForm);
        }
        // 拉丁 -nx→-nges：larynges→larynx、pharynges→pharynx（g→x 替换）
        if (base.endsWith('ng')) {
          add('${base.substring(0, base.length - 1)}x', InflectionType.sForm);
        }
      } else if (spelling.endsWith('s')) {
        add(spelling.substring(0, spelling.length - 1), InflectionType.sForm);
      } else if (spelling.endsWith('men')) {
        // -man 复合词：airmen→airman、women→woman、men→man。
        // 复合词守卫（评审方案 B）：词长 ≥5 且词干 ≥2 字符——挡 omen→oman
        // （Oman 国名在库）、amen 等 4 字词与单字符词干。残余噪声候选
        // （speciman/luman/abdoman/hyman/regiman/numan/noman/bituman）不在词库，
        // 由仓储层查库滤除；库内孪生真词误判（german/soman/yuman/human）
        // 经 _sExceptionWords 早退拦截（carmen/germen/somen/humen/yumen，
        // 全量核对见 resolver 头部注释）。men/women 特例在守卫外直接生成。
        if (spelling == 'men' || spelling == 'women') {
          add('${spelling.substring(0, spelling.length - 3)}man', InflectionType.sForm);
        } else if (spelling.length >= 5) {
          final stem = spelling.substring(0, spelling.length - 3);
          if (stem.length >= 2) {
            add('${stem}man', InflectionType.sForm);
          }
        }
      }
    }

    // ── pastTense：过去式 / 过去分词 ──
    if (spelling.endsWith('ied')) {
      // -ie 动词词族去 d 放首位：died→die（die 在库先命中）、tied→tie；
      // studied→studie 非词，study 兜住（ied→y 兜底）
      add(spelling.substring(0, spelling.length - 1), InflectionType.pastTense); // died→die
      add('${spelling.substring(0, spelling.length - 3)}y', InflectionType.pastTense); // studied→study
      // 直接去 ed：alibied→alibi、skied→ski（放在最后，不抢 -ie/-y 词族）
      add(spelling.substring(0, spelling.length - 2), InflectionType.pastTense);
    } else if (spelling.endsWith('ed')) {
      final base = spelling.substring(0, spelling.length - 2);
      add(base, InflectionType.pastTense); // played→play
      add(_undouble(base), InflectionType.pastTense); // stopped→stop
      add('${base}e', InflectionType.pastTense); // iced→ice
      // -ck→-c：panicked→panic、arcked→arc（plucked 的 pluck 先行命中）
      if (base.endsWith('ck')) {
        add(base.substring(0, base.length - 1), InflectionType.pastTense);
      }
    }

    // ── presentParticiple ──
    if (spelling.endsWith('ing')) {
      final base = spelling.substring(0, spelling.length - 3);
      // -ie 动词词族 ying→ie 放最前：dying→die（die 在库先命中）、lying→lie；
      // 仅当结尾 4 字符为 'ying' 时追加——playing→playie 非词无害，play 其他候选先命中
      if (spelling.endsWith('ying')) {
        add('${spelling.substring(0, spelling.length - 4)}ie', InflectionType.presentParticiple); // dying→die
      }
      add(base, InflectionType.presentParticiple); // going→go
      add(_undouble(base), InflectionType.presentParticiple); // running→run
      add('${base}e', InflectionType.presentParticiple); // making→make
      add('${base}y', InflectionType.presentParticiple); // crying→cry
      // -ck→-c：panicking→panic、arcking→arc
      if (base.endsWith('ck')) {
        add(base.substring(0, base.length - 1), InflectionType.presentParticiple);
      }
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
