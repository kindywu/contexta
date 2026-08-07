import 'package:drift/drift.dart';

/// 词库表组（4 张）：word / word_sense / example_sentence / vocabulary_entry。
/// 逐列对照 Android Room schema：
/// impl/app/android/app/src/main/java/com/ak/contexta/data/local/entity/*.kt
///
/// Room 建表规则（drift 必须逐条一致）：
/// - 禁止 withDefault() —— Room 建表无 DEFAULT，默认值由应用代码填充
/// - 自增主键 → integer().autoIncrement()
/// - 枚举/状态存 TEXT（大写枚举名）
/// - 布尔 → boolean()（drift 生成 CHECK 约束，接受即可）
/// - 索引名与 Room 完全一致（Room 按 表名_列名 自动命名）

/// 表 word（WordEntity.kt）
@DataClassName('WordRow')
@TableIndex(
  name: 'index_word_spelling_normalized',
  columns: {#spellingNormalized},
  unique: true,
)
class Words extends Table {
  /// Room 表名 word（类名复数，必须显式覆盖）
  @override
  String get tableName => 'word';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// lowercase + trimmed, used for lookup, never displayed
  TextColumn get spellingNormalized => text()();

  /// canonical form displayed to user
  TextColumn get spellingDisplay => text()();

  TextColumn? get phoneticIpa => text().nullable()();
}

/// 表 word_sense（WordSenseEntity.kt）
@DataClassName('WordSenseRow')
@TableIndex(
  name: 'index_word_sense_word_id',
  columns: {#wordId},
)
class WordSenses extends Table {
  /// Room 表名 word_sense（类名复数，必须显式覆盖）
  @override
  String get tableName => 'word_sense';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// Room: ForeignKey(WordEntity, parent = id, child = word_id, onDelete = CASCADE)
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();

  /// display order, context-matching sense first (0)
  IntColumn get orderIndex => integer()();

  /// e.g. "n.", "v."
  TextColumn get partOfSpeech => text()();

  TextColumn get chineseMeaning => text()();

  TextColumn get englishDefinition => text()();
}

/// 表 example_sentence（ExampleSentenceEntity.kt）
@DataClassName('ExampleSentenceRow')
@TableIndex(
  name: 'index_example_sentence_word_sense_id',
  columns: {#wordSenseId},
)
class ExampleSentences extends Table {
  /// Room 表名 example_sentence（类名复数，必须显式覆盖）
  @override
  String get tableName => 'example_sentence';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// Room: ForeignKey(WordSenseEntity, parent = id, child = word_sense_id, onDelete = CASCADE)
  IntColumn get wordSenseId =>
      integer().references(WordSenses, #id, onDelete: KeyAction.cascade)();

  IntColumn get orderIndex => integer()();

  TextColumn get sentenceEn => text()();

  TextColumn get sentenceZh => text()();

  /// true = context-matching example from the original article
  BoolColumn get isPrimary => boolean()();
}

/// 表 vocabulary_entry（VocabularyEntryEntity.kt）
///
/// 用户生词表（db:TYPE 关系实体：用户 ↔ 单词 + 掌握状态），
/// 软删除用 deleted_at / deleted_reason（"MANUAL_REMOVAL" | "MASTERED"）。
@DataClassName('VocabularyEntryRow')
@TableIndex(
  name: 'index_vocabulary_entry_word_id',
  columns: {#wordId},
)
class VocabularyEntries extends Table {
  /// Room 表名 vocabulary_entry（类名复数，必须显式覆盖）
  @override
  String get tableName => 'vocabulary_entry';

  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  IntColumn get id => integer().autoIncrement()();

  /// Room: ForeignKey(WordEntity, parent = id, child = word_id, onDelete = CASCADE)
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();

  /// increments each time the same word is re-added
  IntColumn get instanceNumber => integer()();

  /// NEW | LEARNING | MASTERED
  TextColumn get status => text()();

  IntColumn get correctReviewStreak => integer()();

  TextColumn? get masteredAt => text().nullable()();

  /// soft delete
  TextColumn? get deletedAt => text().nullable()();

  /// "MANUAL_REMOVAL" | "MASTERED"
  TextColumn? get deletedReason => text().nullable()();
}
