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

  /// -ss/-us/-is/-as 结尾不去 s（bus、gas、his、analysis 例外）。
  static final _sException = RegExp(r'(ss|us|is|as)$');

  /// 本身是词元的例外词（入口早退，任何段都不解析）：
  /// - "news" 是 mass noun 非复数；ws 结尾不能整体进正则——cows→cow、
  ///   shows→show 是合法复数规则；
  /// - "series"/"species" 单复数同形（拉丁借词），纯后缀规则无法区分
  ///   cities→city 与 series（剥 ies/es 后 "ser" 与 "cit" 结构相同），只能显式例外；
  /// - "her"/"per" 会经 comparative 的 er 分支误生成 h/he/p（元素符号，均在库）；
  /// - "always" 以 s 结尾的非复数实词，会误生成 alway。
  static const _sExceptionWords = {'news', 'series', 'species', 'her', 'per', 'always'};
  static const _minLen = 3;

  @override
  List<InflectionCandidate> resolveCandidates(String spelling) {
    // 例外词本身是词元，任何段都不解析——her/per 的误判路径在 comparative
    // 的 er 分支（her→h/he、per→p），必须在入口早退而非仅拦 sForm 段
    if (_sExceptionWords.contains(spelling)) {
      return const [];
    }
    final out = <InflectionCandidate>[];
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
      // -ie 动词词族去 d 放首位：died→die（die 在库先命中）、tied→tie；
      // studied→studie 非词，study 兜住（ied→y 兜底）
      add(spelling.substring(0, spelling.length - 1), InflectionType.pastTense); // died→die
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
      // -ie 动词词族 ying→ie 放最前：dying→die（die 在库先命中）、lying→lie；
      // 仅当结尾 4 字符为 'ying' 时追加——playing→playie 非词无害，play 其他候选先命中
      if (spelling.endsWith('ying')) {
        add('${spelling.substring(0, spelling.length - 4)}ie', InflectionType.presentParticiple); // dying→die
      }
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
