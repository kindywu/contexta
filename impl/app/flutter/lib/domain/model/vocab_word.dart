import 'word_detail.dart';

/// 生词条目领域模型（对齐 Kotlin VocabWord.kt）。
class VocabWord {
  final int entryId;
  final int wordId;
  final int instanceNumber;
  final VocabStatus status;
  final int correctReviewStreak;
  final String spellingDisplay;
  final String? phoneticIpa;
  final List<WordSense> allSenses;

  const VocabWord({
    required this.entryId,
    required this.wordId,
    required this.instanceNumber,
    required this.status,
    required this.correctReviewStreak,
    required this.spellingDisplay,
    required this.phoneticIpa,
    required this.allSenses,
  });

  @override
  String toString() => 'VocabWord(entryId=$entryId, wordId=$wordId, '
      'instanceNumber=$instanceNumber, status=$status, '
      'correctReviewStreak=$correctReviewStreak, '
      'spellingDisplay=$spellingDisplay, phoneticIpa=$phoneticIpa, '
      'allSenses=$allSenses)';
}

/// 生词掌握状态（对齐 Kotlin VocabStatus；存储层用大写枚举名 TEXT）。
enum VocabStatus {
  new_('NEW'),
  learning('LEARNING'),
  mastered('MASTERED');

  const VocabStatus(this.dbValue);

  /// DB 存储值（大写枚举名）。
  final String dbValue;

  String toDbValue() => dbValue;

  static VocabStatus fromDbValue(String value) {
    for (final s in values) {
      if (s.dbValue == value) return s;
    }
    throw ArgumentError('Unknown VocabStatus: $value');
  }

  @override
  String toString() => dbValue;
}
