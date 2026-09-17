/// 英文句子切分（阅读页「按句朗读 + 按句高亮」的切分依据）。
///
/// 与 [findWordRanges]（word_extractor.dart）同风格：返回原文中的 half-open
/// 区间 `(start, end)`，**不含句子前后的空白**，但包含句末标点与紧随其后的
/// 收尾引号/括号（`He said "Stop." Then…` 的第一句区间覆盖到 `"` 为止）。
///
/// 切分偏保守：**漏切**（两句并作一句）只损失高亮粒度，**误切**（一句拆成
/// 两半）会把句子读音切断——因此歧义处一律不切（缩写、小数、单个大写字母
/// 后跟句点、终止符后接小写字母等）。
library;

/// 句末终止符：`.` `!` `?` `…`（连续出现按一个终止符处理，如 `?!`、`...`）。
bool _isTerminator(String c) =>
    c == '.' || c == '!' || c == '?' || c == '…';

/// 收尾符：跟在终止符之后仍属于本句（引号 / 括号）。
const String _closers = '"\'”’)]}»';

/// 收尾的右括号：句点在括号内（`(about 9 p.m.)`）时，括号闭合即句末——
/// 缩写判定不再适用。
const String _closingBrackets = ')]}';

/// 句首合法字符：终止符后紧跟这些字符视为新句子开始（引号 / 括号开头）。
const String _openers = '"\'“‘«([—';

/// 不切分的缩写词（小写、不含点；多点缩写如 `e.g` / `u.s` 原样收录）。
/// 标题（Mr./Dr./Prof.）、地位（Jr./Sr./St.）、拉丁缩写（e.g./i.e./etc.）、
/// 国名缩写（U.S./U.K.）、时间（a.m./p.m.）、编号（No./Fig./Ch.）等。
const Set<String> _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'st', 'jr', 'sr', 'vs', 'etc',
  'no', 'fig', 'inc', 'ltd', 'co', 'corp', 'dept', 'est', 'approx',
  'min', 'max', 'a.m', 'p.m', 'u.s', 'u.k', 'ph.d', 'b.c', 'a.d',
  'al', 'ed', 'eds', 'vol', 'pp', 'ch', 'sec', 'gen', 'col', 'sgt',
  'capt', 'lt',
};

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isLetter(String c) {
  final code = c.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}

bool _isUpper(String c) {
  final code = c.codeUnitAt(0);
  return code >= 0x41 && code <= 0x5A;
}

/// 从 [from] 起第一个非空白字符；没有则返回 null。
String? _nextMeaningful(String text, int from) {
  for (var i = from; i < text.length; i++) {
    if (!_isSpace(text[i])) return text[i];
  }
  return null;
}

/// 句点前是否是缩写（含单字母首字母缩写，如 `J. K. Rowling`）。
bool _isAbbreviationBefore(String text, int periodIndex) {
  var i = periodIndex - 1;
  while (i >= 0 && (_isLetter(text[i]) || text[i] == '.')) {
    i--;
  }
  final token = text.substring(i + 1, periodIndex).toLowerCase();
  if (token.isEmpty) return false;
  if (token.length == 1) return true; // 单个大写字母 + 点 = 首字母缩写
  return _abbreviations.contains(token);
}

/// `[termStart, termEnd)` 为终止符串，[afterClosers] 为其后收尾符串的终点。
bool _isSentenceEnd(String text, int termStart, int termEnd, int afterClosers) {
  final next = _nextMeaningful(text, afterClosers);
  if (next == null) return true; // 文末，无论标点是什么都收句

  // 单个 '.' 的歧义（缩写 / 小数）：判定为「不切」。收尾符含右括号时
  // 句点位于括号内（`(about 9 p.m.)`），括号闭合即句末，不做缩写判定。
  var bracketed = false;
  for (var i = termEnd; i < afterClosers; i++) {
    if (_closingBrackets.contains(text[i])) {
      bracketed = true;
      break;
    }
  }
  if (!bracketed && termEnd - termStart == 1 && text[termStart] == '.') {
    final prev = termStart > 0 ? text[termStart - 1] : '';
    if (_isDigit(prev) && _isDigit(next)) return false; // 3.14
    if (_isAbbreviationBefore(text, termStart)) return false; // Mr. / U.S. / J.
  }

  // 下一句以大写字母、数字、引号/括号开头才算切；小写开头视为同句
  // （`"Stop!" she shouted.` 这类对话标签不会被误切）
  return _isUpper(next) || _isDigit(next) || _openers.contains(next);
}

/// 在 [text] 中查找所有句子的区间 `(start, end)`（half-open，含句末标点，
/// 不含首尾空白）。空白段落（无任何非空白字符）返回空列表。
List<(int, int)> findSentenceRanges(String text) {
  final ranges = <(int, int)>[];
  final n = text.length;
  var start = -1; // 当前句首个非空白字符下标
  var i = 0;
  while (i < n) {
    final c = text[i];
    if (start < 0) {
      if (_isSpace(c)) {
        i++;
        continue;
      }
      start = i;
    }
    if (!_isTerminator(c)) {
      i++;
      continue;
    }
    var termEnd = i;
    while (termEnd < n && _isTerminator(text[termEnd])) {
      termEnd++;
    }
    var afterClosers = termEnd;
    while (afterClosers < n && _closers.contains(text[afterClosers])) {
      afterClosers++;
    }
    if (_isSentenceEnd(text, i, termEnd, afterClosers)) {
      ranges.add((start, afterClosers));
      start = -1;
    }
    i = afterClosers > i ? afterClosers : i + 1;
  }
  if (start >= 0) {
    var end = n;
    while (end > start && _isSpace(text[end - 1])) {
      end--;
    }
    if (end > start) ranges.add((start, end));
  }
  return ranges;
}

/// 句子文本列表（[findSentenceRanges] 的区间切片）。
List<String> splitSentences(String text) => [
      for (final (start, end) in findSentenceRanges(text))
        text.substring(start, end),
    ];
