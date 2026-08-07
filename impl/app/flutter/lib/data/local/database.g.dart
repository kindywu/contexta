// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, UserSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isOnboardedMeta = const VerificationMeta(
    'isOnboarded',
  );
  @override
  late final GeneratedColumn<bool> isOnboarded = GeneratedColumn<bool>(
    'is_onboarded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_onboarded" IN (0, 1))',
    ),
  );
  static const VerificationMeta _difficultyLevelMeta = const VerificationMeta(
    'difficultyLevel',
  );
  @override
  late final GeneratedColumn<String> difficultyLevel = GeneratedColumn<String>(
    'difficulty_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dailyArticleCountMeta = const VerificationMeta(
    'dailyArticleCount',
  );
  @override
  late final GeneratedColumn<int> dailyArticleCount = GeneratedColumn<int>(
    'daily_article_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _translationDisplayModeMeta =
      const VerificationMeta('translationDisplayMode');
  @override
  late final GeneratedColumn<String> translationDisplayMode =
      GeneratedColumn<String>(
        'translation_display_mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _masteryThresholdNMeta = const VerificationMeta(
    'masteryThresholdN',
  );
  @override
  late final GeneratedColumn<int> masteryThresholdN = GeneratedColumn<int>(
    'mastery_threshold_n',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _autoPlayAudioMeta = const VerificationMeta(
    'autoPlayAudio',
  );
  @override
  late final GeneratedColumn<bool> autoPlayAudio = GeneratedColumn<bool>(
    'auto_play_audio',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_play_audio" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isOnboarded,
    difficultyLevel,
    dailyArticleCount,
    translationDisplayMode,
    masteryThresholdN,
    autoPlayAudio,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('is_onboarded')) {
      context.handle(
        _isOnboardedMeta,
        isOnboarded.isAcceptableOrUnknown(
          data['is_onboarded']!,
          _isOnboardedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isOnboardedMeta);
    }
    if (data.containsKey('difficulty_level')) {
      context.handle(
        _difficultyLevelMeta,
        difficultyLevel.isAcceptableOrUnknown(
          data['difficulty_level']!,
          _difficultyLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_difficultyLevelMeta);
    }
    if (data.containsKey('daily_article_count')) {
      context.handle(
        _dailyArticleCountMeta,
        dailyArticleCount.isAcceptableOrUnknown(
          data['daily_article_count']!,
          _dailyArticleCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dailyArticleCountMeta);
    }
    if (data.containsKey('translation_display_mode')) {
      context.handle(
        _translationDisplayModeMeta,
        translationDisplayMode.isAcceptableOrUnknown(
          data['translation_display_mode']!,
          _translationDisplayModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_translationDisplayModeMeta);
    }
    if (data.containsKey('mastery_threshold_n')) {
      context.handle(
        _masteryThresholdNMeta,
        masteryThresholdN.isAcceptableOrUnknown(
          data['mastery_threshold_n']!,
          _masteryThresholdNMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_masteryThresholdNMeta);
    }
    if (data.containsKey('auto_play_audio')) {
      context.handle(
        _autoPlayAudioMeta,
        autoPlayAudio.isAcceptableOrUnknown(
          data['auto_play_audio']!,
          _autoPlayAudioMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_autoPlayAudioMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isOnboarded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_onboarded'],
      )!,
      difficultyLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}difficulty_level'],
      )!,
      dailyArticleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_article_count'],
      )!,
      translationDisplayMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}translation_display_mode'],
      )!,
      masteryThresholdN: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mastery_threshold_n'],
      )!,
      autoPlayAudio: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_play_audio'],
      )!,
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }
}

class UserSettingsRow extends DataClass implements Insertable<UserSettingsRow> {
  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  final int id;
  final bool isOnboarded;

  /// LOW | MEDIUM | HIGH（枚举存 TEXT 枚举名）
  final String difficultyLevel;
  final int dailyArticleCount;

  /// FULL | BLURRED | HIDDEN
  final String translationDisplayMode;
  final int masteryThresholdN;
  final bool autoPlayAudio;
  const UserSettingsRow({
    required this.id,
    required this.isOnboarded,
    required this.difficultyLevel,
    required this.dailyArticleCount,
    required this.translationDisplayMode,
    required this.masteryThresholdN,
    required this.autoPlayAudio,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['is_onboarded'] = Variable<bool>(isOnboarded);
    map['difficulty_level'] = Variable<String>(difficultyLevel);
    map['daily_article_count'] = Variable<int>(dailyArticleCount);
    map['translation_display_mode'] = Variable<String>(translationDisplayMode);
    map['mastery_threshold_n'] = Variable<int>(masteryThresholdN);
    map['auto_play_audio'] = Variable<bool>(autoPlayAudio);
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(
      id: Value(id),
      isOnboarded: Value(isOnboarded),
      difficultyLevel: Value(difficultyLevel),
      dailyArticleCount: Value(dailyArticleCount),
      translationDisplayMode: Value(translationDisplayMode),
      masteryThresholdN: Value(masteryThresholdN),
      autoPlayAudio: Value(autoPlayAudio),
    );
  }

  factory UserSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      isOnboarded: serializer.fromJson<bool>(json['isOnboarded']),
      difficultyLevel: serializer.fromJson<String>(json['difficultyLevel']),
      dailyArticleCount: serializer.fromJson<int>(json['dailyArticleCount']),
      translationDisplayMode: serializer.fromJson<String>(
        json['translationDisplayMode'],
      ),
      masteryThresholdN: serializer.fromJson<int>(json['masteryThresholdN']),
      autoPlayAudio: serializer.fromJson<bool>(json['autoPlayAudio']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isOnboarded': serializer.toJson<bool>(isOnboarded),
      'difficultyLevel': serializer.toJson<String>(difficultyLevel),
      'dailyArticleCount': serializer.toJson<int>(dailyArticleCount),
      'translationDisplayMode': serializer.toJson<String>(
        translationDisplayMode,
      ),
      'masteryThresholdN': serializer.toJson<int>(masteryThresholdN),
      'autoPlayAudio': serializer.toJson<bool>(autoPlayAudio),
    };
  }

  UserSettingsRow copyWith({
    int? id,
    bool? isOnboarded,
    String? difficultyLevel,
    int? dailyArticleCount,
    String? translationDisplayMode,
    int? masteryThresholdN,
    bool? autoPlayAudio,
  }) => UserSettingsRow(
    id: id ?? this.id,
    isOnboarded: isOnboarded ?? this.isOnboarded,
    difficultyLevel: difficultyLevel ?? this.difficultyLevel,
    dailyArticleCount: dailyArticleCount ?? this.dailyArticleCount,
    translationDisplayMode:
        translationDisplayMode ?? this.translationDisplayMode,
    masteryThresholdN: masteryThresholdN ?? this.masteryThresholdN,
    autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
  );
  UserSettingsRow copyWithCompanion(UserSettingsCompanion data) {
    return UserSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      isOnboarded: data.isOnboarded.present
          ? data.isOnboarded.value
          : this.isOnboarded,
      difficultyLevel: data.difficultyLevel.present
          ? data.difficultyLevel.value
          : this.difficultyLevel,
      dailyArticleCount: data.dailyArticleCount.present
          ? data.dailyArticleCount.value
          : this.dailyArticleCount,
      translationDisplayMode: data.translationDisplayMode.present
          ? data.translationDisplayMode.value
          : this.translationDisplayMode,
      masteryThresholdN: data.masteryThresholdN.present
          ? data.masteryThresholdN.value
          : this.masteryThresholdN,
      autoPlayAudio: data.autoPlayAudio.present
          ? data.autoPlayAudio.value
          : this.autoPlayAudio,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsRow(')
          ..write('id: $id, ')
          ..write('isOnboarded: $isOnboarded, ')
          ..write('difficultyLevel: $difficultyLevel, ')
          ..write('dailyArticleCount: $dailyArticleCount, ')
          ..write('translationDisplayMode: $translationDisplayMode, ')
          ..write('masteryThresholdN: $masteryThresholdN, ')
          ..write('autoPlayAudio: $autoPlayAudio')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isOnboarded,
    difficultyLevel,
    dailyArticleCount,
    translationDisplayMode,
    masteryThresholdN,
    autoPlayAudio,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSettingsRow &&
          other.id == this.id &&
          other.isOnboarded == this.isOnboarded &&
          other.difficultyLevel == this.difficultyLevel &&
          other.dailyArticleCount == this.dailyArticleCount &&
          other.translationDisplayMode == this.translationDisplayMode &&
          other.masteryThresholdN == this.masteryThresholdN &&
          other.autoPlayAudio == this.autoPlayAudio);
}

class UserSettingsCompanion extends UpdateCompanion<UserSettingsRow> {
  final Value<int> id;
  final Value<bool> isOnboarded;
  final Value<String> difficultyLevel;
  final Value<int> dailyArticleCount;
  final Value<String> translationDisplayMode;
  final Value<int> masteryThresholdN;
  final Value<bool> autoPlayAudio;
  const UserSettingsCompanion({
    this.id = const Value.absent(),
    this.isOnboarded = const Value.absent(),
    this.difficultyLevel = const Value.absent(),
    this.dailyArticleCount = const Value.absent(),
    this.translationDisplayMode = const Value.absent(),
    this.masteryThresholdN = const Value.absent(),
    this.autoPlayAudio = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    this.id = const Value.absent(),
    required bool isOnboarded,
    required String difficultyLevel,
    required int dailyArticleCount,
    required String translationDisplayMode,
    required int masteryThresholdN,
    required bool autoPlayAudio,
  }) : isOnboarded = Value(isOnboarded),
       difficultyLevel = Value(difficultyLevel),
       dailyArticleCount = Value(dailyArticleCount),
       translationDisplayMode = Value(translationDisplayMode),
       masteryThresholdN = Value(masteryThresholdN),
       autoPlayAudio = Value(autoPlayAudio);
  static Insertable<UserSettingsRow> custom({
    Expression<int>? id,
    Expression<bool>? isOnboarded,
    Expression<String>? difficultyLevel,
    Expression<int>? dailyArticleCount,
    Expression<String>? translationDisplayMode,
    Expression<int>? masteryThresholdN,
    Expression<bool>? autoPlayAudio,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isOnboarded != null) 'is_onboarded': isOnboarded,
      if (difficultyLevel != null) 'difficulty_level': difficultyLevel,
      if (dailyArticleCount != null) 'daily_article_count': dailyArticleCount,
      if (translationDisplayMode != null)
        'translation_display_mode': translationDisplayMode,
      if (masteryThresholdN != null) 'mastery_threshold_n': masteryThresholdN,
      if (autoPlayAudio != null) 'auto_play_audio': autoPlayAudio,
    });
  }

  UserSettingsCompanion copyWith({
    Value<int>? id,
    Value<bool>? isOnboarded,
    Value<String>? difficultyLevel,
    Value<int>? dailyArticleCount,
    Value<String>? translationDisplayMode,
    Value<int>? masteryThresholdN,
    Value<bool>? autoPlayAudio,
  }) {
    return UserSettingsCompanion(
      id: id ?? this.id,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      difficultyLevel: difficultyLevel ?? this.difficultyLevel,
      dailyArticleCount: dailyArticleCount ?? this.dailyArticleCount,
      translationDisplayMode:
          translationDisplayMode ?? this.translationDisplayMode,
      masteryThresholdN: masteryThresholdN ?? this.masteryThresholdN,
      autoPlayAudio: autoPlayAudio ?? this.autoPlayAudio,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isOnboarded.present) {
      map['is_onboarded'] = Variable<bool>(isOnboarded.value);
    }
    if (difficultyLevel.present) {
      map['difficulty_level'] = Variable<String>(difficultyLevel.value);
    }
    if (dailyArticleCount.present) {
      map['daily_article_count'] = Variable<int>(dailyArticleCount.value);
    }
    if (translationDisplayMode.present) {
      map['translation_display_mode'] = Variable<String>(
        translationDisplayMode.value,
      );
    }
    if (masteryThresholdN.present) {
      map['mastery_threshold_n'] = Variable<int>(masteryThresholdN.value);
    }
    if (autoPlayAudio.present) {
      map['auto_play_audio'] = Variable<bool>(autoPlayAudio.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('id: $id, ')
          ..write('isOnboarded: $isOnboarded, ')
          ..write('difficultyLevel: $difficultyLevel, ')
          ..write('dailyArticleCount: $dailyArticleCount, ')
          ..write('translationDisplayMode: $translationDisplayMode, ')
          ..write('masteryThresholdN: $masteryThresholdN, ')
          ..write('autoPlayAudio: $autoPlayAudio')
          ..write(')'))
        .toString();
  }
}

class $ConfigChangeLogsTable extends ConfigChangeLogs
    with TableInfo<$ConfigChangeLogsTable, ConfigChangeLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConfigChangeLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fieldNameMeta = const VerificationMeta(
    'fieldName',
  );
  @override
  late final GeneratedColumn<String> fieldName = GeneratedColumn<String>(
    'field_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oldValueMeta = const VerificationMeta(
    'oldValue',
  );
  @override
  late final GeneratedColumn<String> oldValue = GeneratedColumn<String>(
    'old_value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _newValueMeta = const VerificationMeta(
    'newValue',
  );
  @override
  late final GeneratedColumn<String> newValue = GeneratedColumn<String>(
    'new_value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fieldName,
    oldValue,
    newValue,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'config_change_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConfigChangeLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('field_name')) {
      context.handle(
        _fieldNameMeta,
        fieldName.isAcceptableOrUnknown(data['field_name']!, _fieldNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldNameMeta);
    }
    if (data.containsKey('old_value')) {
      context.handle(
        _oldValueMeta,
        oldValue.isAcceptableOrUnknown(data['old_value']!, _oldValueMeta),
      );
    } else if (isInserting) {
      context.missing(_oldValueMeta);
    }
    if (data.containsKey('new_value')) {
      context.handle(
        _newValueMeta,
        newValue.isAcceptableOrUnknown(data['new_value']!, _newValueMeta),
      );
    } else if (isInserting) {
      context.missing(_newValueMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConfigChangeLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConfigChangeLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fieldName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_name'],
      )!,
      oldValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}old_value'],
      )!,
      newValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_value'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ConfigChangeLogsTable createAlias(String alias) {
    return $ConfigChangeLogsTable(attachedDatabase, alias);
  }
}

class ConfigChangeLogRow extends DataClass
    implements Insertable<ConfigChangeLogRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// currently only "daily_article_count"
  final String fieldName;
  final String oldValue;
  final String newValue;
  final String createdAt;
  const ConfigChangeLogRow({
    required this.id,
    required this.fieldName,
    required this.oldValue,
    required this.newValue,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['field_name'] = Variable<String>(fieldName);
    map['old_value'] = Variable<String>(oldValue);
    map['new_value'] = Variable<String>(newValue);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  ConfigChangeLogsCompanion toCompanion(bool nullToAbsent) {
    return ConfigChangeLogsCompanion(
      id: Value(id),
      fieldName: Value(fieldName),
      oldValue: Value(oldValue),
      newValue: Value(newValue),
      createdAt: Value(createdAt),
    );
  }

  factory ConfigChangeLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConfigChangeLogRow(
      id: serializer.fromJson<int>(json['id']),
      fieldName: serializer.fromJson<String>(json['fieldName']),
      oldValue: serializer.fromJson<String>(json['oldValue']),
      newValue: serializer.fromJson<String>(json['newValue']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fieldName': serializer.toJson<String>(fieldName),
      'oldValue': serializer.toJson<String>(oldValue),
      'newValue': serializer.toJson<String>(newValue),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  ConfigChangeLogRow copyWith({
    int? id,
    String? fieldName,
    String? oldValue,
    String? newValue,
    String? createdAt,
  }) => ConfigChangeLogRow(
    id: id ?? this.id,
    fieldName: fieldName ?? this.fieldName,
    oldValue: oldValue ?? this.oldValue,
    newValue: newValue ?? this.newValue,
    createdAt: createdAt ?? this.createdAt,
  );
  ConfigChangeLogRow copyWithCompanion(ConfigChangeLogsCompanion data) {
    return ConfigChangeLogRow(
      id: data.id.present ? data.id.value : this.id,
      fieldName: data.fieldName.present ? data.fieldName.value : this.fieldName,
      oldValue: data.oldValue.present ? data.oldValue.value : this.oldValue,
      newValue: data.newValue.present ? data.newValue.value : this.newValue,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConfigChangeLogRow(')
          ..write('id: $id, ')
          ..write('fieldName: $fieldName, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fieldName, oldValue, newValue, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConfigChangeLogRow &&
          other.id == this.id &&
          other.fieldName == this.fieldName &&
          other.oldValue == this.oldValue &&
          other.newValue == this.newValue &&
          other.createdAt == this.createdAt);
}

class ConfigChangeLogsCompanion extends UpdateCompanion<ConfigChangeLogRow> {
  final Value<int> id;
  final Value<String> fieldName;
  final Value<String> oldValue;
  final Value<String> newValue;
  final Value<String> createdAt;
  const ConfigChangeLogsCompanion({
    this.id = const Value.absent(),
    this.fieldName = const Value.absent(),
    this.oldValue = const Value.absent(),
    this.newValue = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ConfigChangeLogsCompanion.insert({
    this.id = const Value.absent(),
    required String fieldName,
    required String oldValue,
    required String newValue,
    required String createdAt,
  }) : fieldName = Value(fieldName),
       oldValue = Value(oldValue),
       newValue = Value(newValue),
       createdAt = Value(createdAt);
  static Insertable<ConfigChangeLogRow> custom({
    Expression<int>? id,
    Expression<String>? fieldName,
    Expression<String>? oldValue,
    Expression<String>? newValue,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fieldName != null) 'field_name': fieldName,
      if (oldValue != null) 'old_value': oldValue,
      if (newValue != null) 'new_value': newValue,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ConfigChangeLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? fieldName,
    Value<String>? oldValue,
    Value<String>? newValue,
    Value<String>? createdAt,
  }) {
    return ConfigChangeLogsCompanion(
      id: id ?? this.id,
      fieldName: fieldName ?? this.fieldName,
      oldValue: oldValue ?? this.oldValue,
      newValue: newValue ?? this.newValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fieldName.present) {
      map['field_name'] = Variable<String>(fieldName.value);
    }
    if (oldValue.present) {
      map['old_value'] = Variable<String>(oldValue.value);
    }
    if (newValue.present) {
      map['new_value'] = Variable<String>(newValue.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConfigChangeLogsCompanion(')
          ..write('id: $id, ')
          ..write('fieldName: $fieldName, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SchemaMigrationLogsTable extends SchemaMigrationLogs
    with TableInfo<$SchemaMigrationLogsTable, SchemaMigrationLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchemaMigrationLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fromVersionMeta = const VerificationMeta(
    'fromVersion',
  );
  @override
  late final GeneratedColumn<int> fromVersion = GeneratedColumn<int>(
    'from_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toVersionMeta = const VerificationMeta(
    'toVersion',
  );
  @override
  late final GeneratedColumn<int> toVersion = GeneratedColumn<int>(
    'to_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fromVersion,
    toVersion,
    description,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schema_migration_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<SchemaMigrationLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('from_version')) {
      context.handle(
        _fromVersionMeta,
        fromVersion.isAcceptableOrUnknown(
          data['from_version']!,
          _fromVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromVersionMeta);
    }
    if (data.containsKey('to_version')) {
      context.handle(
        _toVersionMeta,
        toVersion.isAcceptableOrUnknown(data['to_version']!, _toVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_toVersionMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SchemaMigrationLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SchemaMigrationLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fromVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}from_version'],
      )!,
      toVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_version'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SchemaMigrationLogsTable createAlias(String alias) {
    return $SchemaMigrationLogsTable(attachedDatabase, alias);
  }
}

class SchemaMigrationLogRow extends DataClass
    implements Insertable<SchemaMigrationLogRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;
  final int fromVersion;
  final int toVersion;
  final String description;
  final String createdAt;
  const SchemaMigrationLogRow({
    required this.id,
    required this.fromVersion,
    required this.toVersion,
    required this.description,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['from_version'] = Variable<int>(fromVersion);
    map['to_version'] = Variable<int>(toVersion);
    map['description'] = Variable<String>(description);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  SchemaMigrationLogsCompanion toCompanion(bool nullToAbsent) {
    return SchemaMigrationLogsCompanion(
      id: Value(id),
      fromVersion: Value(fromVersion),
      toVersion: Value(toVersion),
      description: Value(description),
      createdAt: Value(createdAt),
    );
  }

  factory SchemaMigrationLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SchemaMigrationLogRow(
      id: serializer.fromJson<int>(json['id']),
      fromVersion: serializer.fromJson<int>(json['fromVersion']),
      toVersion: serializer.fromJson<int>(json['toVersion']),
      description: serializer.fromJson<String>(json['description']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fromVersion': serializer.toJson<int>(fromVersion),
      'toVersion': serializer.toJson<int>(toVersion),
      'description': serializer.toJson<String>(description),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  SchemaMigrationLogRow copyWith({
    int? id,
    int? fromVersion,
    int? toVersion,
    String? description,
    String? createdAt,
  }) => SchemaMigrationLogRow(
    id: id ?? this.id,
    fromVersion: fromVersion ?? this.fromVersion,
    toVersion: toVersion ?? this.toVersion,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
  );
  SchemaMigrationLogRow copyWithCompanion(SchemaMigrationLogsCompanion data) {
    return SchemaMigrationLogRow(
      id: data.id.present ? data.id.value : this.id,
      fromVersion: data.fromVersion.present
          ? data.fromVersion.value
          : this.fromVersion,
      toVersion: data.toVersion.present ? data.toVersion.value : this.toVersion,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SchemaMigrationLogRow(')
          ..write('id: $id, ')
          ..write('fromVersion: $fromVersion, ')
          ..write('toVersion: $toVersion, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fromVersion, toVersion, description, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SchemaMigrationLogRow &&
          other.id == this.id &&
          other.fromVersion == this.fromVersion &&
          other.toVersion == this.toVersion &&
          other.description == this.description &&
          other.createdAt == this.createdAt);
}

class SchemaMigrationLogsCompanion
    extends UpdateCompanion<SchemaMigrationLogRow> {
  final Value<int> id;
  final Value<int> fromVersion;
  final Value<int> toVersion;
  final Value<String> description;
  final Value<String> createdAt;
  const SchemaMigrationLogsCompanion({
    this.id = const Value.absent(),
    this.fromVersion = const Value.absent(),
    this.toVersion = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SchemaMigrationLogsCompanion.insert({
    this.id = const Value.absent(),
    required int fromVersion,
    required int toVersion,
    required String description,
    required String createdAt,
  }) : fromVersion = Value(fromVersion),
       toVersion = Value(toVersion),
       description = Value(description),
       createdAt = Value(createdAt);
  static Insertable<SchemaMigrationLogRow> custom({
    Expression<int>? id,
    Expression<int>? fromVersion,
    Expression<int>? toVersion,
    Expression<String>? description,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromVersion != null) 'from_version': fromVersion,
      if (toVersion != null) 'to_version': toVersion,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SchemaMigrationLogsCompanion copyWith({
    Value<int>? id,
    Value<int>? fromVersion,
    Value<int>? toVersion,
    Value<String>? description,
    Value<String>? createdAt,
  }) {
    return SchemaMigrationLogsCompanion(
      id: id ?? this.id,
      fromVersion: fromVersion ?? this.fromVersion,
      toVersion: toVersion ?? this.toVersion,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fromVersion.present) {
      map['from_version'] = Variable<int>(fromVersion.value);
    }
    if (toVersion.present) {
      map['to_version'] = Variable<int>(toVersion.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchemaMigrationLogsCompanion(')
          ..write('id: $id, ')
          ..write('fromVersion: $fromVersion, ')
          ..write('toVersion: $toVersion, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $GenerationPipelineStatusesTable extends GenerationPipelineStatuses
    with
        TableInfo<
          $GenerationPipelineStatusesTable,
          GenerationPipelineStatusRow
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GenerationPipelineStatusesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isBlockedMeta = const VerificationMeta(
    'isBlocked',
  );
  @override
  late final GeneratedColumn<bool> isBlocked = GeneratedColumn<bool>(
    'is_blocked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_blocked" IN (0, 1))',
    ),
  );
  static const VerificationMeta _blockedReasonMeta = const VerificationMeta(
    'blockedReason',
  );
  @override
  late final GeneratedColumn<String> blockedReason = GeneratedColumn<String>(
    'blocked_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockedAtMeta = const VerificationMeta(
    'blockedAt',
  );
  @override
  late final GeneratedColumn<String> blockedAt = GeneratedColumn<String>(
    'blocked_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockedAppVersionCodeMeta =
      const VerificationMeta('blockedAppVersionCode');
  @override
  late final GeneratedColumn<int> blockedAppVersionCode = GeneratedColumn<int>(
    'blocked_app_version_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isBlocked,
    blockedReason,
    blockedAt,
    blockedAppVersionCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'generation_pipeline_status';
  @override
  VerificationContext validateIntegrity(
    Insertable<GenerationPipelineStatusRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('is_blocked')) {
      context.handle(
        _isBlockedMeta,
        isBlocked.isAcceptableOrUnknown(data['is_blocked']!, _isBlockedMeta),
      );
    } else if (isInserting) {
      context.missing(_isBlockedMeta);
    }
    if (data.containsKey('blocked_reason')) {
      context.handle(
        _blockedReasonMeta,
        blockedReason.isAcceptableOrUnknown(
          data['blocked_reason']!,
          _blockedReasonMeta,
        ),
      );
    }
    if (data.containsKey('blocked_at')) {
      context.handle(
        _blockedAtMeta,
        blockedAt.isAcceptableOrUnknown(data['blocked_at']!, _blockedAtMeta),
      );
    }
    if (data.containsKey('blocked_app_version_code')) {
      context.handle(
        _blockedAppVersionCodeMeta,
        blockedAppVersionCode.isAcceptableOrUnknown(
          data['blocked_app_version_code']!,
          _blockedAppVersionCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GenerationPipelineStatusRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GenerationPipelineStatusRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isBlocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_blocked'],
      )!,
      blockedReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocked_reason'],
      ),
      blockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocked_at'],
      ),
      blockedAppVersionCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}blocked_app_version_code'],
      ),
    );
  }

  @override
  $GenerationPipelineStatusesTable createAlias(String alias) {
    return $GenerationPipelineStatusesTable(attachedDatabase, alias);
  }
}

class GenerationPipelineStatusRow extends DataClass
    implements Insertable<GenerationPipelineStatusRow> {
  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  final int id;
  final bool isBlocked;
  final String? blockedReason;
  final String? blockedAt;
  final int? blockedAppVersionCode;
  const GenerationPipelineStatusRow({
    required this.id,
    required this.isBlocked,
    this.blockedReason,
    this.blockedAt,
    this.blockedAppVersionCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['is_blocked'] = Variable<bool>(isBlocked);
    if (!nullToAbsent || blockedReason != null) {
      map['blocked_reason'] = Variable<String>(blockedReason);
    }
    if (!nullToAbsent || blockedAt != null) {
      map['blocked_at'] = Variable<String>(blockedAt);
    }
    if (!nullToAbsent || blockedAppVersionCode != null) {
      map['blocked_app_version_code'] = Variable<int>(blockedAppVersionCode);
    }
    return map;
  }

  GenerationPipelineStatusesCompanion toCompanion(bool nullToAbsent) {
    return GenerationPipelineStatusesCompanion(
      id: Value(id),
      isBlocked: Value(isBlocked),
      blockedReason: blockedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedReason),
      blockedAt: blockedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedAt),
      blockedAppVersionCode: blockedAppVersionCode == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedAppVersionCode),
    );
  }

  factory GenerationPipelineStatusRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GenerationPipelineStatusRow(
      id: serializer.fromJson<int>(json['id']),
      isBlocked: serializer.fromJson<bool>(json['isBlocked']),
      blockedReason: serializer.fromJson<String?>(json['blockedReason']),
      blockedAt: serializer.fromJson<String?>(json['blockedAt']),
      blockedAppVersionCode: serializer.fromJson<int?>(
        json['blockedAppVersionCode'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isBlocked': serializer.toJson<bool>(isBlocked),
      'blockedReason': serializer.toJson<String?>(blockedReason),
      'blockedAt': serializer.toJson<String?>(blockedAt),
      'blockedAppVersionCode': serializer.toJson<int?>(blockedAppVersionCode),
    };
  }

  GenerationPipelineStatusRow copyWith({
    int? id,
    bool? isBlocked,
    Value<String?> blockedReason = const Value.absent(),
    Value<String?> blockedAt = const Value.absent(),
    Value<int?> blockedAppVersionCode = const Value.absent(),
  }) => GenerationPipelineStatusRow(
    id: id ?? this.id,
    isBlocked: isBlocked ?? this.isBlocked,
    blockedReason: blockedReason.present
        ? blockedReason.value
        : this.blockedReason,
    blockedAt: blockedAt.present ? blockedAt.value : this.blockedAt,
    blockedAppVersionCode: blockedAppVersionCode.present
        ? blockedAppVersionCode.value
        : this.blockedAppVersionCode,
  );
  GenerationPipelineStatusRow copyWithCompanion(
    GenerationPipelineStatusesCompanion data,
  ) {
    return GenerationPipelineStatusRow(
      id: data.id.present ? data.id.value : this.id,
      isBlocked: data.isBlocked.present ? data.isBlocked.value : this.isBlocked,
      blockedReason: data.blockedReason.present
          ? data.blockedReason.value
          : this.blockedReason,
      blockedAt: data.blockedAt.present ? data.blockedAt.value : this.blockedAt,
      blockedAppVersionCode: data.blockedAppVersionCode.present
          ? data.blockedAppVersionCode.value
          : this.blockedAppVersionCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GenerationPipelineStatusRow(')
          ..write('id: $id, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('blockedAppVersionCode: $blockedAppVersionCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isBlocked,
    blockedReason,
    blockedAt,
    blockedAppVersionCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GenerationPipelineStatusRow &&
          other.id == this.id &&
          other.isBlocked == this.isBlocked &&
          other.blockedReason == this.blockedReason &&
          other.blockedAt == this.blockedAt &&
          other.blockedAppVersionCode == this.blockedAppVersionCode);
}

class GenerationPipelineStatusesCompanion
    extends UpdateCompanion<GenerationPipelineStatusRow> {
  final Value<int> id;
  final Value<bool> isBlocked;
  final Value<String?> blockedReason;
  final Value<String?> blockedAt;
  final Value<int?> blockedAppVersionCode;
  const GenerationPipelineStatusesCompanion({
    this.id = const Value.absent(),
    this.isBlocked = const Value.absent(),
    this.blockedReason = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.blockedAppVersionCode = const Value.absent(),
  });
  GenerationPipelineStatusesCompanion.insert({
    this.id = const Value.absent(),
    required bool isBlocked,
    this.blockedReason = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.blockedAppVersionCode = const Value.absent(),
  }) : isBlocked = Value(isBlocked);
  static Insertable<GenerationPipelineStatusRow> custom({
    Expression<int>? id,
    Expression<bool>? isBlocked,
    Expression<String>? blockedReason,
    Expression<String>? blockedAt,
    Expression<int>? blockedAppVersionCode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isBlocked != null) 'is_blocked': isBlocked,
      if (blockedReason != null) 'blocked_reason': blockedReason,
      if (blockedAt != null) 'blocked_at': blockedAt,
      if (blockedAppVersionCode != null)
        'blocked_app_version_code': blockedAppVersionCode,
    });
  }

  GenerationPipelineStatusesCompanion copyWith({
    Value<int>? id,
    Value<bool>? isBlocked,
    Value<String?>? blockedReason,
    Value<String?>? blockedAt,
    Value<int?>? blockedAppVersionCode,
  }) {
    return GenerationPipelineStatusesCompanion(
      id: id ?? this.id,
      isBlocked: isBlocked ?? this.isBlocked,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedAt: blockedAt ?? this.blockedAt,
      blockedAppVersionCode:
          blockedAppVersionCode ?? this.blockedAppVersionCode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isBlocked.present) {
      map['is_blocked'] = Variable<bool>(isBlocked.value);
    }
    if (blockedReason.present) {
      map['blocked_reason'] = Variable<String>(blockedReason.value);
    }
    if (blockedAt.present) {
      map['blocked_at'] = Variable<String>(blockedAt.value);
    }
    if (blockedAppVersionCode.present) {
      map['blocked_app_version_code'] = Variable<int>(
        blockedAppVersionCode.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GenerationPipelineStatusesCompanion(')
          ..write('id: $id, ')
          ..write('isBlocked: $isBlocked, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('blockedAppVersionCode: $blockedAppVersionCode')
          ..write(')'))
        .toString();
  }
}

class $DailyLearningLogsTable extends DailyLearningLogs
    with TableInfo<$DailyLearningLogsTable, DailyLearningLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLearningLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _logDateMeta = const VerificationMeta(
    'logDate',
  );
  @override
  late final GeneratedColumn<String> logDate = GeneratedColumn<String>(
    'log_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _articlesReadMeta = const VerificationMeta(
    'articlesRead',
  );
  @override
  late final GeneratedColumn<int> articlesRead = GeneratedColumn<int>(
    'articles_read',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordsAddedMeta = const VerificationMeta(
    'wordsAdded',
  );
  @override
  late final GeneratedColumn<int> wordsAdded = GeneratedColumn<int>(
    'words_added',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secondsSpentMeta = const VerificationMeta(
    'secondsSpent',
  );
  @override
  late final GeneratedColumn<int> secondsSpent = GeneratedColumn<int>(
    'seconds_spent',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    logDate,
    articlesRead,
    wordsAdded,
    secondsSpent,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_learning_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLearningLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('log_date')) {
      context.handle(
        _logDateMeta,
        logDate.isAcceptableOrUnknown(data['log_date']!, _logDateMeta),
      );
    } else if (isInserting) {
      context.missing(_logDateMeta);
    }
    if (data.containsKey('articles_read')) {
      context.handle(
        _articlesReadMeta,
        articlesRead.isAcceptableOrUnknown(
          data['articles_read']!,
          _articlesReadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_articlesReadMeta);
    }
    if (data.containsKey('words_added')) {
      context.handle(
        _wordsAddedMeta,
        wordsAdded.isAcceptableOrUnknown(data['words_added']!, _wordsAddedMeta),
      );
    } else if (isInserting) {
      context.missing(_wordsAddedMeta);
    }
    if (data.containsKey('seconds_spent')) {
      context.handle(
        _secondsSpentMeta,
        secondsSpent.isAcceptableOrUnknown(
          data['seconds_spent']!,
          _secondsSpentMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_secondsSpentMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DailyLearningLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLearningLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      logDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}log_date'],
      )!,
      articlesRead: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}articles_read'],
      )!,
      wordsAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}words_added'],
      )!,
      secondsSpent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seconds_spent'],
      )!,
    );
  }

  @override
  $DailyLearningLogsTable createAlias(String alias) {
    return $DailyLearningLogsTable(attachedDatabase, alias);
  }
}

class DailyLearningLogRow extends DataClass
    implements Insertable<DailyLearningLogRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// ISO date "2026-07-29"
  final String logDate;
  final int articlesRead;
  final int wordsAdded;
  final int secondsSpent;
  const DailyLearningLogRow({
    required this.id,
    required this.logDate,
    required this.articlesRead,
    required this.wordsAdded,
    required this.secondsSpent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['log_date'] = Variable<String>(logDate);
    map['articles_read'] = Variable<int>(articlesRead);
    map['words_added'] = Variable<int>(wordsAdded);
    map['seconds_spent'] = Variable<int>(secondsSpent);
    return map;
  }

  DailyLearningLogsCompanion toCompanion(bool nullToAbsent) {
    return DailyLearningLogsCompanion(
      id: Value(id),
      logDate: Value(logDate),
      articlesRead: Value(articlesRead),
      wordsAdded: Value(wordsAdded),
      secondsSpent: Value(secondsSpent),
    );
  }

  factory DailyLearningLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLearningLogRow(
      id: serializer.fromJson<int>(json['id']),
      logDate: serializer.fromJson<String>(json['logDate']),
      articlesRead: serializer.fromJson<int>(json['articlesRead']),
      wordsAdded: serializer.fromJson<int>(json['wordsAdded']),
      secondsSpent: serializer.fromJson<int>(json['secondsSpent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'logDate': serializer.toJson<String>(logDate),
      'articlesRead': serializer.toJson<int>(articlesRead),
      'wordsAdded': serializer.toJson<int>(wordsAdded),
      'secondsSpent': serializer.toJson<int>(secondsSpent),
    };
  }

  DailyLearningLogRow copyWith({
    int? id,
    String? logDate,
    int? articlesRead,
    int? wordsAdded,
    int? secondsSpent,
  }) => DailyLearningLogRow(
    id: id ?? this.id,
    logDate: logDate ?? this.logDate,
    articlesRead: articlesRead ?? this.articlesRead,
    wordsAdded: wordsAdded ?? this.wordsAdded,
    secondsSpent: secondsSpent ?? this.secondsSpent,
  );
  DailyLearningLogRow copyWithCompanion(DailyLearningLogsCompanion data) {
    return DailyLearningLogRow(
      id: data.id.present ? data.id.value : this.id,
      logDate: data.logDate.present ? data.logDate.value : this.logDate,
      articlesRead: data.articlesRead.present
          ? data.articlesRead.value
          : this.articlesRead,
      wordsAdded: data.wordsAdded.present
          ? data.wordsAdded.value
          : this.wordsAdded,
      secondsSpent: data.secondsSpent.present
          ? data.secondsSpent.value
          : this.secondsSpent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLearningLogRow(')
          ..write('id: $id, ')
          ..write('logDate: $logDate, ')
          ..write('articlesRead: $articlesRead, ')
          ..write('wordsAdded: $wordsAdded, ')
          ..write('secondsSpent: $secondsSpent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, logDate, articlesRead, wordsAdded, secondsSpent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLearningLogRow &&
          other.id == this.id &&
          other.logDate == this.logDate &&
          other.articlesRead == this.articlesRead &&
          other.wordsAdded == this.wordsAdded &&
          other.secondsSpent == this.secondsSpent);
}

class DailyLearningLogsCompanion extends UpdateCompanion<DailyLearningLogRow> {
  final Value<int> id;
  final Value<String> logDate;
  final Value<int> articlesRead;
  final Value<int> wordsAdded;
  final Value<int> secondsSpent;
  const DailyLearningLogsCompanion({
    this.id = const Value.absent(),
    this.logDate = const Value.absent(),
    this.articlesRead = const Value.absent(),
    this.wordsAdded = const Value.absent(),
    this.secondsSpent = const Value.absent(),
  });
  DailyLearningLogsCompanion.insert({
    this.id = const Value.absent(),
    required String logDate,
    required int articlesRead,
    required int wordsAdded,
    required int secondsSpent,
  }) : logDate = Value(logDate),
       articlesRead = Value(articlesRead),
       wordsAdded = Value(wordsAdded),
       secondsSpent = Value(secondsSpent);
  static Insertable<DailyLearningLogRow> custom({
    Expression<int>? id,
    Expression<String>? logDate,
    Expression<int>? articlesRead,
    Expression<int>? wordsAdded,
    Expression<int>? secondsSpent,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (logDate != null) 'log_date': logDate,
      if (articlesRead != null) 'articles_read': articlesRead,
      if (wordsAdded != null) 'words_added': wordsAdded,
      if (secondsSpent != null) 'seconds_spent': secondsSpent,
    });
  }

  DailyLearningLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? logDate,
    Value<int>? articlesRead,
    Value<int>? wordsAdded,
    Value<int>? secondsSpent,
  }) {
    return DailyLearningLogsCompanion(
      id: id ?? this.id,
      logDate: logDate ?? this.logDate,
      articlesRead: articlesRead ?? this.articlesRead,
      wordsAdded: wordsAdded ?? this.wordsAdded,
      secondsSpent: secondsSpent ?? this.secondsSpent,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (logDate.present) {
      map['log_date'] = Variable<String>(logDate.value);
    }
    if (articlesRead.present) {
      map['articles_read'] = Variable<int>(articlesRead.value);
    }
    if (wordsAdded.present) {
      map['words_added'] = Variable<int>(wordsAdded.value);
    }
    if (secondsSpent.present) {
      map['seconds_spent'] = Variable<int>(secondsSpent.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLearningLogsCompanion(')
          ..write('id: $id, ')
          ..write('logDate: $logDate, ')
          ..write('articlesRead: $articlesRead, ')
          ..write('wordsAdded: $wordsAdded, ')
          ..write('secondsSpent: $secondsSpent')
          ..write(')'))
        .toString();
  }
}

class $LearningStatsSummariesTable extends LearningStatsSummaries
    with TableInfo<$LearningStatsSummariesTable, LearningStatsSummaryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LearningStatsSummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalArticlesReadMeta = const VerificationMeta(
    'totalArticlesRead',
  );
  @override
  late final GeneratedColumn<int> totalArticlesRead = GeneratedColumn<int>(
    'total_articles_read',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalWordsAddedMeta = const VerificationMeta(
    'totalWordsAdded',
  );
  @override
  late final GeneratedColumn<int> totalWordsAdded = GeneratedColumn<int>(
    'total_words_added',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalWordsMasteredMeta =
      const VerificationMeta('totalWordsMastered');
  @override
  late final GeneratedColumn<int> totalWordsMastered = GeneratedColumn<int>(
    'total_words_mastered',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalLearningDaysMeta = const VerificationMeta(
    'totalLearningDays',
  );
  @override
  late final GeneratedColumn<int> totalLearningDays = GeneratedColumn<int>(
    'total_learning_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentStreakMeta = const VerificationMeta(
    'currentStreak',
  );
  @override
  late final GeneratedColumn<int> currentStreak = GeneratedColumn<int>(
    'current_streak',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longestStreakMeta = const VerificationMeta(
    'longestStreak',
  );
  @override
  late final GeneratedColumn<int> longestStreak = GeneratedColumn<int>(
    'longest_streak',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastActiveDateMeta = const VerificationMeta(
    'lastActiveDate',
  );
  @override
  late final GeneratedColumn<String> lastActiveDate = GeneratedColumn<String>(
    'last_active_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    totalArticlesRead,
    totalWordsAdded,
    totalWordsMastered,
    totalLearningDays,
    currentStreak,
    longestStreak,
    lastActiveDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'learning_stats_summary';
  @override
  VerificationContext validateIntegrity(
    Insertable<LearningStatsSummaryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('total_articles_read')) {
      context.handle(
        _totalArticlesReadMeta,
        totalArticlesRead.isAcceptableOrUnknown(
          data['total_articles_read']!,
          _totalArticlesReadMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalArticlesReadMeta);
    }
    if (data.containsKey('total_words_added')) {
      context.handle(
        _totalWordsAddedMeta,
        totalWordsAdded.isAcceptableOrUnknown(
          data['total_words_added']!,
          _totalWordsAddedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalWordsAddedMeta);
    }
    if (data.containsKey('total_words_mastered')) {
      context.handle(
        _totalWordsMasteredMeta,
        totalWordsMastered.isAcceptableOrUnknown(
          data['total_words_mastered']!,
          _totalWordsMasteredMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalWordsMasteredMeta);
    }
    if (data.containsKey('total_learning_days')) {
      context.handle(
        _totalLearningDaysMeta,
        totalLearningDays.isAcceptableOrUnknown(
          data['total_learning_days']!,
          _totalLearningDaysMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_totalLearningDaysMeta);
    }
    if (data.containsKey('current_streak')) {
      context.handle(
        _currentStreakMeta,
        currentStreak.isAcceptableOrUnknown(
          data['current_streak']!,
          _currentStreakMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentStreakMeta);
    }
    if (data.containsKey('longest_streak')) {
      context.handle(
        _longestStreakMeta,
        longestStreak.isAcceptableOrUnknown(
          data['longest_streak']!,
          _longestStreakMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_longestStreakMeta);
    }
    if (data.containsKey('last_active_date')) {
      context.handle(
        _lastActiveDateMeta,
        lastActiveDate.isAcceptableOrUnknown(
          data['last_active_date']!,
          _lastActiveDateMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LearningStatsSummaryRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LearningStatsSummaryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      totalArticlesRead: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_articles_read'],
      )!,
      totalWordsAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_words_added'],
      )!,
      totalWordsMastered: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_words_mastered'],
      )!,
      totalLearningDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_learning_days'],
      )!,
      currentStreak: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_streak'],
      )!,
      longestStreak: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}longest_streak'],
      )!,
      lastActiveDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_active_date'],
      ),
    );
  }

  @override
  $LearningStatsSummariesTable createAlias(String alias) {
    return $LearningStatsSummariesTable(attachedDatabase, alias);
  }
}

class LearningStatsSummaryRow extends DataClass
    implements Insertable<LearningStatsSummaryRow> {
  /// Room: @PrimaryKey val id: Int（无 autoGenerate）
  final int id;
  final int totalArticlesRead;
  final int totalWordsAdded;
  final int totalWordsMastered;
  final int totalLearningDays;
  final int currentStreak;
  final int longestStreak;

  /// ISO date
  final String? lastActiveDate;
  const LearningStatsSummaryRow({
    required this.id,
    required this.totalArticlesRead,
    required this.totalWordsAdded,
    required this.totalWordsMastered,
    required this.totalLearningDays,
    required this.currentStreak,
    required this.longestStreak,
    this.lastActiveDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['total_articles_read'] = Variable<int>(totalArticlesRead);
    map['total_words_added'] = Variable<int>(totalWordsAdded);
    map['total_words_mastered'] = Variable<int>(totalWordsMastered);
    map['total_learning_days'] = Variable<int>(totalLearningDays);
    map['current_streak'] = Variable<int>(currentStreak);
    map['longest_streak'] = Variable<int>(longestStreak);
    if (!nullToAbsent || lastActiveDate != null) {
      map['last_active_date'] = Variable<String>(lastActiveDate);
    }
    return map;
  }

  LearningStatsSummariesCompanion toCompanion(bool nullToAbsent) {
    return LearningStatsSummariesCompanion(
      id: Value(id),
      totalArticlesRead: Value(totalArticlesRead),
      totalWordsAdded: Value(totalWordsAdded),
      totalWordsMastered: Value(totalWordsMastered),
      totalLearningDays: Value(totalLearningDays),
      currentStreak: Value(currentStreak),
      longestStreak: Value(longestStreak),
      lastActiveDate: lastActiveDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastActiveDate),
    );
  }

  factory LearningStatsSummaryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LearningStatsSummaryRow(
      id: serializer.fromJson<int>(json['id']),
      totalArticlesRead: serializer.fromJson<int>(json['totalArticlesRead']),
      totalWordsAdded: serializer.fromJson<int>(json['totalWordsAdded']),
      totalWordsMastered: serializer.fromJson<int>(json['totalWordsMastered']),
      totalLearningDays: serializer.fromJson<int>(json['totalLearningDays']),
      currentStreak: serializer.fromJson<int>(json['currentStreak']),
      longestStreak: serializer.fromJson<int>(json['longestStreak']),
      lastActiveDate: serializer.fromJson<String?>(json['lastActiveDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'totalArticlesRead': serializer.toJson<int>(totalArticlesRead),
      'totalWordsAdded': serializer.toJson<int>(totalWordsAdded),
      'totalWordsMastered': serializer.toJson<int>(totalWordsMastered),
      'totalLearningDays': serializer.toJson<int>(totalLearningDays),
      'currentStreak': serializer.toJson<int>(currentStreak),
      'longestStreak': serializer.toJson<int>(longestStreak),
      'lastActiveDate': serializer.toJson<String?>(lastActiveDate),
    };
  }

  LearningStatsSummaryRow copyWith({
    int? id,
    int? totalArticlesRead,
    int? totalWordsAdded,
    int? totalWordsMastered,
    int? totalLearningDays,
    int? currentStreak,
    int? longestStreak,
    Value<String?> lastActiveDate = const Value.absent(),
  }) => LearningStatsSummaryRow(
    id: id ?? this.id,
    totalArticlesRead: totalArticlesRead ?? this.totalArticlesRead,
    totalWordsAdded: totalWordsAdded ?? this.totalWordsAdded,
    totalWordsMastered: totalWordsMastered ?? this.totalWordsMastered,
    totalLearningDays: totalLearningDays ?? this.totalLearningDays,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    lastActiveDate: lastActiveDate.present
        ? lastActiveDate.value
        : this.lastActiveDate,
  );
  LearningStatsSummaryRow copyWithCompanion(
    LearningStatsSummariesCompanion data,
  ) {
    return LearningStatsSummaryRow(
      id: data.id.present ? data.id.value : this.id,
      totalArticlesRead: data.totalArticlesRead.present
          ? data.totalArticlesRead.value
          : this.totalArticlesRead,
      totalWordsAdded: data.totalWordsAdded.present
          ? data.totalWordsAdded.value
          : this.totalWordsAdded,
      totalWordsMastered: data.totalWordsMastered.present
          ? data.totalWordsMastered.value
          : this.totalWordsMastered,
      totalLearningDays: data.totalLearningDays.present
          ? data.totalLearningDays.value
          : this.totalLearningDays,
      currentStreak: data.currentStreak.present
          ? data.currentStreak.value
          : this.currentStreak,
      longestStreak: data.longestStreak.present
          ? data.longestStreak.value
          : this.longestStreak,
      lastActiveDate: data.lastActiveDate.present
          ? data.lastActiveDate.value
          : this.lastActiveDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LearningStatsSummaryRow(')
          ..write('id: $id, ')
          ..write('totalArticlesRead: $totalArticlesRead, ')
          ..write('totalWordsAdded: $totalWordsAdded, ')
          ..write('totalWordsMastered: $totalWordsMastered, ')
          ..write('totalLearningDays: $totalLearningDays, ')
          ..write('currentStreak: $currentStreak, ')
          ..write('longestStreak: $longestStreak, ')
          ..write('lastActiveDate: $lastActiveDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    totalArticlesRead,
    totalWordsAdded,
    totalWordsMastered,
    totalLearningDays,
    currentStreak,
    longestStreak,
    lastActiveDate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LearningStatsSummaryRow &&
          other.id == this.id &&
          other.totalArticlesRead == this.totalArticlesRead &&
          other.totalWordsAdded == this.totalWordsAdded &&
          other.totalWordsMastered == this.totalWordsMastered &&
          other.totalLearningDays == this.totalLearningDays &&
          other.currentStreak == this.currentStreak &&
          other.longestStreak == this.longestStreak &&
          other.lastActiveDate == this.lastActiveDate);
}

class LearningStatsSummariesCompanion
    extends UpdateCompanion<LearningStatsSummaryRow> {
  final Value<int> id;
  final Value<int> totalArticlesRead;
  final Value<int> totalWordsAdded;
  final Value<int> totalWordsMastered;
  final Value<int> totalLearningDays;
  final Value<int> currentStreak;
  final Value<int> longestStreak;
  final Value<String?> lastActiveDate;
  const LearningStatsSummariesCompanion({
    this.id = const Value.absent(),
    this.totalArticlesRead = const Value.absent(),
    this.totalWordsAdded = const Value.absent(),
    this.totalWordsMastered = const Value.absent(),
    this.totalLearningDays = const Value.absent(),
    this.currentStreak = const Value.absent(),
    this.longestStreak = const Value.absent(),
    this.lastActiveDate = const Value.absent(),
  });
  LearningStatsSummariesCompanion.insert({
    this.id = const Value.absent(),
    required int totalArticlesRead,
    required int totalWordsAdded,
    required int totalWordsMastered,
    required int totalLearningDays,
    required int currentStreak,
    required int longestStreak,
    this.lastActiveDate = const Value.absent(),
  }) : totalArticlesRead = Value(totalArticlesRead),
       totalWordsAdded = Value(totalWordsAdded),
       totalWordsMastered = Value(totalWordsMastered),
       totalLearningDays = Value(totalLearningDays),
       currentStreak = Value(currentStreak),
       longestStreak = Value(longestStreak);
  static Insertable<LearningStatsSummaryRow> custom({
    Expression<int>? id,
    Expression<int>? totalArticlesRead,
    Expression<int>? totalWordsAdded,
    Expression<int>? totalWordsMastered,
    Expression<int>? totalLearningDays,
    Expression<int>? currentStreak,
    Expression<int>? longestStreak,
    Expression<String>? lastActiveDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (totalArticlesRead != null) 'total_articles_read': totalArticlesRead,
      if (totalWordsAdded != null) 'total_words_added': totalWordsAdded,
      if (totalWordsMastered != null)
        'total_words_mastered': totalWordsMastered,
      if (totalLearningDays != null) 'total_learning_days': totalLearningDays,
      if (currentStreak != null) 'current_streak': currentStreak,
      if (longestStreak != null) 'longest_streak': longestStreak,
      if (lastActiveDate != null) 'last_active_date': lastActiveDate,
    });
  }

  LearningStatsSummariesCompanion copyWith({
    Value<int>? id,
    Value<int>? totalArticlesRead,
    Value<int>? totalWordsAdded,
    Value<int>? totalWordsMastered,
    Value<int>? totalLearningDays,
    Value<int>? currentStreak,
    Value<int>? longestStreak,
    Value<String?>? lastActiveDate,
  }) {
    return LearningStatsSummariesCompanion(
      id: id ?? this.id,
      totalArticlesRead: totalArticlesRead ?? this.totalArticlesRead,
      totalWordsAdded: totalWordsAdded ?? this.totalWordsAdded,
      totalWordsMastered: totalWordsMastered ?? this.totalWordsMastered,
      totalLearningDays: totalLearningDays ?? this.totalLearningDays,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (totalArticlesRead.present) {
      map['total_articles_read'] = Variable<int>(totalArticlesRead.value);
    }
    if (totalWordsAdded.present) {
      map['total_words_added'] = Variable<int>(totalWordsAdded.value);
    }
    if (totalWordsMastered.present) {
      map['total_words_mastered'] = Variable<int>(totalWordsMastered.value);
    }
    if (totalLearningDays.present) {
      map['total_learning_days'] = Variable<int>(totalLearningDays.value);
    }
    if (currentStreak.present) {
      map['current_streak'] = Variable<int>(currentStreak.value);
    }
    if (longestStreak.present) {
      map['longest_streak'] = Variable<int>(longestStreak.value);
    }
    if (lastActiveDate.present) {
      map['last_active_date'] = Variable<String>(lastActiveDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LearningStatsSummariesCompanion(')
          ..write('id: $id, ')
          ..write('totalArticlesRead: $totalArticlesRead, ')
          ..write('totalWordsAdded: $totalWordsAdded, ')
          ..write('totalWordsMastered: $totalWordsMastered, ')
          ..write('totalLearningDays: $totalLearningDays, ')
          ..write('currentStreak: $currentStreak, ')
          ..write('longestStreak: $longestStreak, ')
          ..write('lastActiveDate: $lastActiveDate')
          ..write(')'))
        .toString();
  }
}

class $ArticleBatchesTable extends ArticleBatches
    with TableInfo<$ArticleBatchesTable, ArticleBatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticleBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _difficultyLevelSnapshotMeta =
      const VerificationMeta('difficultyLevelSnapshot');
  @override
  late final GeneratedColumn<String> difficultyLevelSnapshot =
      GeneratedColumn<String>(
        'difficulty_level_snapshot',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _generatedOnMeta = const VerificationMeta(
    'generatedOn',
  );
  @override
  late final GeneratedColumn<String> generatedOn = GeneratedColumn<String>(
    'generated_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUpdatedAtMeta = const VerificationMeta(
    'lastUpdatedAt',
  );
  @override
  late final GeneratedColumn<String> lastUpdatedAt = GeneratedColumn<String>(
    'last_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockedReasonMeta = const VerificationMeta(
    'blockedReason',
  );
  @override
  late final GeneratedColumn<String> blockedReason = GeneratedColumn<String>(
    'blocked_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockedAtMeta = const VerificationMeta(
    'blockedAt',
  );
  @override
  late final GeneratedColumn<String> blockedAt = GeneratedColumn<String>(
    'blocked_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readyNotifiedAtMeta = const VerificationMeta(
    'readyNotifiedAt',
  );
  @override
  late final GeneratedColumn<int> readyNotifiedAt = GeneratedColumn<int>(
    'ready_notified_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    status,
    difficultyLevelSnapshot,
    generatedOn,
    lastUpdatedAt,
    blockedReason,
    blockedAt,
    readyNotifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_batch';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArticleBatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('difficulty_level_snapshot')) {
      context.handle(
        _difficultyLevelSnapshotMeta,
        difficultyLevelSnapshot.isAcceptableOrUnknown(
          data['difficulty_level_snapshot']!,
          _difficultyLevelSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_difficultyLevelSnapshotMeta);
    }
    if (data.containsKey('generated_on')) {
      context.handle(
        _generatedOnMeta,
        generatedOn.isAcceptableOrUnknown(
          data['generated_on']!,
          _generatedOnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generatedOnMeta);
    }
    if (data.containsKey('last_updated_at')) {
      context.handle(
        _lastUpdatedAtMeta,
        lastUpdatedAt.isAcceptableOrUnknown(
          data['last_updated_at']!,
          _lastUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUpdatedAtMeta);
    }
    if (data.containsKey('blocked_reason')) {
      context.handle(
        _blockedReasonMeta,
        blockedReason.isAcceptableOrUnknown(
          data['blocked_reason']!,
          _blockedReasonMeta,
        ),
      );
    }
    if (data.containsKey('blocked_at')) {
      context.handle(
        _blockedAtMeta,
        blockedAt.isAcceptableOrUnknown(data['blocked_at']!, _blockedAtMeta),
      );
    }
    if (data.containsKey('ready_notified_at')) {
      context.handle(
        _readyNotifiedAtMeta,
        readyNotifiedAt.isAcceptableOrUnknown(
          data['ready_notified_at']!,
          _readyNotifiedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArticleBatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticleBatchRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      difficultyLevelSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}difficulty_level_snapshot'],
      )!,
      generatedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generated_on'],
      )!,
      lastUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_updated_at'],
      )!,
      blockedReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocked_reason'],
      ),
      blockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocked_at'],
      ),
      readyNotifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ready_notified_at'],
      ),
    );
  }

  @override
  $ArticleBatchesTable createAlias(String alias) {
    return $ArticleBatchesTable(attachedDatabase, alias);
  }
}

class ArticleBatchRow extends DataClass implements Insertable<ArticleBatchRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// PENDING | GENERATING | READY | CURRENT | BLOCKED
  final String status;
  final String difficultyLevelSnapshot;

  /// ISO date
  final String generatedOn;
  final String lastUpdatedAt;
  final String? blockedReason;
  final String? blockedAt;

  /// 批次完成飞书告警送达时间（Unix millis）；null = 未通知，启动时补发
  final int? readyNotifiedAt;
  const ArticleBatchRow({
    required this.id,
    required this.status,
    required this.difficultyLevelSnapshot,
    required this.generatedOn,
    required this.lastUpdatedAt,
    this.blockedReason,
    this.blockedAt,
    this.readyNotifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['status'] = Variable<String>(status);
    map['difficulty_level_snapshot'] = Variable<String>(
      difficultyLevelSnapshot,
    );
    map['generated_on'] = Variable<String>(generatedOn);
    map['last_updated_at'] = Variable<String>(lastUpdatedAt);
    if (!nullToAbsent || blockedReason != null) {
      map['blocked_reason'] = Variable<String>(blockedReason);
    }
    if (!nullToAbsent || blockedAt != null) {
      map['blocked_at'] = Variable<String>(blockedAt);
    }
    if (!nullToAbsent || readyNotifiedAt != null) {
      map['ready_notified_at'] = Variable<int>(readyNotifiedAt);
    }
    return map;
  }

  ArticleBatchesCompanion toCompanion(bool nullToAbsent) {
    return ArticleBatchesCompanion(
      id: Value(id),
      status: Value(status),
      difficultyLevelSnapshot: Value(difficultyLevelSnapshot),
      generatedOn: Value(generatedOn),
      lastUpdatedAt: Value(lastUpdatedAt),
      blockedReason: blockedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedReason),
      blockedAt: blockedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedAt),
      readyNotifiedAt: readyNotifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readyNotifiedAt),
    );
  }

  factory ArticleBatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticleBatchRow(
      id: serializer.fromJson<int>(json['id']),
      status: serializer.fromJson<String>(json['status']),
      difficultyLevelSnapshot: serializer.fromJson<String>(
        json['difficultyLevelSnapshot'],
      ),
      generatedOn: serializer.fromJson<String>(json['generatedOn']),
      lastUpdatedAt: serializer.fromJson<String>(json['lastUpdatedAt']),
      blockedReason: serializer.fromJson<String?>(json['blockedReason']),
      blockedAt: serializer.fromJson<String?>(json['blockedAt']),
      readyNotifiedAt: serializer.fromJson<int?>(json['readyNotifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'status': serializer.toJson<String>(status),
      'difficultyLevelSnapshot': serializer.toJson<String>(
        difficultyLevelSnapshot,
      ),
      'generatedOn': serializer.toJson<String>(generatedOn),
      'lastUpdatedAt': serializer.toJson<String>(lastUpdatedAt),
      'blockedReason': serializer.toJson<String?>(blockedReason),
      'blockedAt': serializer.toJson<String?>(blockedAt),
      'readyNotifiedAt': serializer.toJson<int?>(readyNotifiedAt),
    };
  }

  ArticleBatchRow copyWith({
    int? id,
    String? status,
    String? difficultyLevelSnapshot,
    String? generatedOn,
    String? lastUpdatedAt,
    Value<String?> blockedReason = const Value.absent(),
    Value<String?> blockedAt = const Value.absent(),
    Value<int?> readyNotifiedAt = const Value.absent(),
  }) => ArticleBatchRow(
    id: id ?? this.id,
    status: status ?? this.status,
    difficultyLevelSnapshot:
        difficultyLevelSnapshot ?? this.difficultyLevelSnapshot,
    generatedOn: generatedOn ?? this.generatedOn,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    blockedReason: blockedReason.present
        ? blockedReason.value
        : this.blockedReason,
    blockedAt: blockedAt.present ? blockedAt.value : this.blockedAt,
    readyNotifiedAt: readyNotifiedAt.present
        ? readyNotifiedAt.value
        : this.readyNotifiedAt,
  );
  ArticleBatchRow copyWithCompanion(ArticleBatchesCompanion data) {
    return ArticleBatchRow(
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      difficultyLevelSnapshot: data.difficultyLevelSnapshot.present
          ? data.difficultyLevelSnapshot.value
          : this.difficultyLevelSnapshot,
      generatedOn: data.generatedOn.present
          ? data.generatedOn.value
          : this.generatedOn,
      lastUpdatedAt: data.lastUpdatedAt.present
          ? data.lastUpdatedAt.value
          : this.lastUpdatedAt,
      blockedReason: data.blockedReason.present
          ? data.blockedReason.value
          : this.blockedReason,
      blockedAt: data.blockedAt.present ? data.blockedAt.value : this.blockedAt,
      readyNotifiedAt: data.readyNotifiedAt.present
          ? data.readyNotifiedAt.value
          : this.readyNotifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticleBatchRow(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('difficultyLevelSnapshot: $difficultyLevelSnapshot, ')
          ..write('generatedOn: $generatedOn, ')
          ..write('lastUpdatedAt: $lastUpdatedAt, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('readyNotifiedAt: $readyNotifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    difficultyLevelSnapshot,
    generatedOn,
    lastUpdatedAt,
    blockedReason,
    blockedAt,
    readyNotifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticleBatchRow &&
          other.id == this.id &&
          other.status == this.status &&
          other.difficultyLevelSnapshot == this.difficultyLevelSnapshot &&
          other.generatedOn == this.generatedOn &&
          other.lastUpdatedAt == this.lastUpdatedAt &&
          other.blockedReason == this.blockedReason &&
          other.blockedAt == this.blockedAt &&
          other.readyNotifiedAt == this.readyNotifiedAt);
}

class ArticleBatchesCompanion extends UpdateCompanion<ArticleBatchRow> {
  final Value<int> id;
  final Value<String> status;
  final Value<String> difficultyLevelSnapshot;
  final Value<String> generatedOn;
  final Value<String> lastUpdatedAt;
  final Value<String?> blockedReason;
  final Value<String?> blockedAt;
  final Value<int?> readyNotifiedAt;
  const ArticleBatchesCompanion({
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.difficultyLevelSnapshot = const Value.absent(),
    this.generatedOn = const Value.absent(),
    this.lastUpdatedAt = const Value.absent(),
    this.blockedReason = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.readyNotifiedAt = const Value.absent(),
  });
  ArticleBatchesCompanion.insert({
    this.id = const Value.absent(),
    required String status,
    required String difficultyLevelSnapshot,
    required String generatedOn,
    required String lastUpdatedAt,
    this.blockedReason = const Value.absent(),
    this.blockedAt = const Value.absent(),
    this.readyNotifiedAt = const Value.absent(),
  }) : status = Value(status),
       difficultyLevelSnapshot = Value(difficultyLevelSnapshot),
       generatedOn = Value(generatedOn),
       lastUpdatedAt = Value(lastUpdatedAt);
  static Insertable<ArticleBatchRow> custom({
    Expression<int>? id,
    Expression<String>? status,
    Expression<String>? difficultyLevelSnapshot,
    Expression<String>? generatedOn,
    Expression<String>? lastUpdatedAt,
    Expression<String>? blockedReason,
    Expression<String>? blockedAt,
    Expression<int>? readyNotifiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (difficultyLevelSnapshot != null)
        'difficulty_level_snapshot': difficultyLevelSnapshot,
      if (generatedOn != null) 'generated_on': generatedOn,
      if (lastUpdatedAt != null) 'last_updated_at': lastUpdatedAt,
      if (blockedReason != null) 'blocked_reason': blockedReason,
      if (blockedAt != null) 'blocked_at': blockedAt,
      if (readyNotifiedAt != null) 'ready_notified_at': readyNotifiedAt,
    });
  }

  ArticleBatchesCompanion copyWith({
    Value<int>? id,
    Value<String>? status,
    Value<String>? difficultyLevelSnapshot,
    Value<String>? generatedOn,
    Value<String>? lastUpdatedAt,
    Value<String?>? blockedReason,
    Value<String?>? blockedAt,
    Value<int?>? readyNotifiedAt,
  }) {
    return ArticleBatchesCompanion(
      id: id ?? this.id,
      status: status ?? this.status,
      difficultyLevelSnapshot:
          difficultyLevelSnapshot ?? this.difficultyLevelSnapshot,
      generatedOn: generatedOn ?? this.generatedOn,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedAt: blockedAt ?? this.blockedAt,
      readyNotifiedAt: readyNotifiedAt ?? this.readyNotifiedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (difficultyLevelSnapshot.present) {
      map['difficulty_level_snapshot'] = Variable<String>(
        difficultyLevelSnapshot.value,
      );
    }
    if (generatedOn.present) {
      map['generated_on'] = Variable<String>(generatedOn.value);
    }
    if (lastUpdatedAt.present) {
      map['last_updated_at'] = Variable<String>(lastUpdatedAt.value);
    }
    if (blockedReason.present) {
      map['blocked_reason'] = Variable<String>(blockedReason.value);
    }
    if (blockedAt.present) {
      map['blocked_at'] = Variable<String>(blockedAt.value);
    }
    if (readyNotifiedAt.present) {
      map['ready_notified_at'] = Variable<int>(readyNotifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticleBatchesCompanion(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('difficultyLevelSnapshot: $difficultyLevelSnapshot, ')
          ..write('generatedOn: $generatedOn, ')
          ..write('lastUpdatedAt: $lastUpdatedAt, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('blockedAt: $blockedAt, ')
          ..write('readyNotifiedAt: $readyNotifiedAt')
          ..write(')'))
        .toString();
  }
}

class $DailyLearningsTable extends DailyLearnings
    with TableInfo<$DailyLearningsTable, DailyLearningRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLearningsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _learningDateMeta = const VerificationMeta(
    'learningDate',
  );
  @override
  late final GeneratedColumn<String> learningDate = GeneratedColumn<String>(
    'learning_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refBatchDateMeta = const VerificationMeta(
    'refBatchDate',
  );
  @override
  late final GeneratedColumn<String> refBatchDate = GeneratedColumn<String>(
    'ref_batch_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refBatchIdMeta = const VerificationMeta(
    'refBatchId',
  );
  @override
  late final GeneratedColumn<int> refBatchId = GeneratedColumn<int>(
    'ref_batch_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES article_batch (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _dailyCountSnapshotMeta =
      const VerificationMeta('dailyCountSnapshot');
  @override
  late final GeneratedColumn<int> dailyCountSnapshot = GeneratedColumn<int>(
    'daily_count_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    learningDate,
    refBatchDate,
    refBatchId,
    dailyCountSnapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_learning';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLearningRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('learning_date')) {
      context.handle(
        _learningDateMeta,
        learningDate.isAcceptableOrUnknown(
          data['learning_date']!,
          _learningDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_learningDateMeta);
    }
    if (data.containsKey('ref_batch_date')) {
      context.handle(
        _refBatchDateMeta,
        refBatchDate.isAcceptableOrUnknown(
          data['ref_batch_date']!,
          _refBatchDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refBatchDateMeta);
    }
    if (data.containsKey('ref_batch_id')) {
      context.handle(
        _refBatchIdMeta,
        refBatchId.isAcceptableOrUnknown(
          data['ref_batch_id']!,
          _refBatchIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refBatchIdMeta);
    }
    if (data.containsKey('daily_count_snapshot')) {
      context.handle(
        _dailyCountSnapshotMeta,
        dailyCountSnapshot.isAcceptableOrUnknown(
          data['daily_count_snapshot']!,
          _dailyCountSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dailyCountSnapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {learningDate};
  @override
  DailyLearningRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLearningRow(
      learningDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}learning_date'],
      )!,
      refBatchDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_batch_date'],
      )!,
      refBatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ref_batch_id'],
      )!,
      dailyCountSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_count_snapshot'],
      )!,
    );
  }

  @override
  $DailyLearningsTable createAlias(String alias) {
    return $DailyLearningsTable(attachedDatabase, alias);
  }
}

class DailyLearningRow extends DataClass
    implements Insertable<DailyLearningRow> {
  /// Room: @PrimaryKey @ColumnInfo(name = "learning_date")（TEXT 主键，无自增）
  final String learningDate;

  /// article_batch.generated_on
  final String refBatchDate;

  /// Room: ForeignKey(ArticleBatchEntity, parent = id, child = ref_batch_id, onDelete = CASCADE)
  final int refBatchId;

  /// 用户设置快照
  final int dailyCountSnapshot;
  const DailyLearningRow({
    required this.learningDate,
    required this.refBatchDate,
    required this.refBatchId,
    required this.dailyCountSnapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['learning_date'] = Variable<String>(learningDate);
    map['ref_batch_date'] = Variable<String>(refBatchDate);
    map['ref_batch_id'] = Variable<int>(refBatchId);
    map['daily_count_snapshot'] = Variable<int>(dailyCountSnapshot);
    return map;
  }

  DailyLearningsCompanion toCompanion(bool nullToAbsent) {
    return DailyLearningsCompanion(
      learningDate: Value(learningDate),
      refBatchDate: Value(refBatchDate),
      refBatchId: Value(refBatchId),
      dailyCountSnapshot: Value(dailyCountSnapshot),
    );
  }

  factory DailyLearningRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLearningRow(
      learningDate: serializer.fromJson<String>(json['learningDate']),
      refBatchDate: serializer.fromJson<String>(json['refBatchDate']),
      refBatchId: serializer.fromJson<int>(json['refBatchId']),
      dailyCountSnapshot: serializer.fromJson<int>(json['dailyCountSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'learningDate': serializer.toJson<String>(learningDate),
      'refBatchDate': serializer.toJson<String>(refBatchDate),
      'refBatchId': serializer.toJson<int>(refBatchId),
      'dailyCountSnapshot': serializer.toJson<int>(dailyCountSnapshot),
    };
  }

  DailyLearningRow copyWith({
    String? learningDate,
    String? refBatchDate,
    int? refBatchId,
    int? dailyCountSnapshot,
  }) => DailyLearningRow(
    learningDate: learningDate ?? this.learningDate,
    refBatchDate: refBatchDate ?? this.refBatchDate,
    refBatchId: refBatchId ?? this.refBatchId,
    dailyCountSnapshot: dailyCountSnapshot ?? this.dailyCountSnapshot,
  );
  DailyLearningRow copyWithCompanion(DailyLearningsCompanion data) {
    return DailyLearningRow(
      learningDate: data.learningDate.present
          ? data.learningDate.value
          : this.learningDate,
      refBatchDate: data.refBatchDate.present
          ? data.refBatchDate.value
          : this.refBatchDate,
      refBatchId: data.refBatchId.present
          ? data.refBatchId.value
          : this.refBatchId,
      dailyCountSnapshot: data.dailyCountSnapshot.present
          ? data.dailyCountSnapshot.value
          : this.dailyCountSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLearningRow(')
          ..write('learningDate: $learningDate, ')
          ..write('refBatchDate: $refBatchDate, ')
          ..write('refBatchId: $refBatchId, ')
          ..write('dailyCountSnapshot: $dailyCountSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(learningDate, refBatchDate, refBatchId, dailyCountSnapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLearningRow &&
          other.learningDate == this.learningDate &&
          other.refBatchDate == this.refBatchDate &&
          other.refBatchId == this.refBatchId &&
          other.dailyCountSnapshot == this.dailyCountSnapshot);
}

class DailyLearningsCompanion extends UpdateCompanion<DailyLearningRow> {
  final Value<String> learningDate;
  final Value<String> refBatchDate;
  final Value<int> refBatchId;
  final Value<int> dailyCountSnapshot;
  final Value<int> rowid;
  const DailyLearningsCompanion({
    this.learningDate = const Value.absent(),
    this.refBatchDate = const Value.absent(),
    this.refBatchId = const Value.absent(),
    this.dailyCountSnapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyLearningsCompanion.insert({
    required String learningDate,
    required String refBatchDate,
    required int refBatchId,
    required int dailyCountSnapshot,
    this.rowid = const Value.absent(),
  }) : learningDate = Value(learningDate),
       refBatchDate = Value(refBatchDate),
       refBatchId = Value(refBatchId),
       dailyCountSnapshot = Value(dailyCountSnapshot);
  static Insertable<DailyLearningRow> custom({
    Expression<String>? learningDate,
    Expression<String>? refBatchDate,
    Expression<int>? refBatchId,
    Expression<int>? dailyCountSnapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (learningDate != null) 'learning_date': learningDate,
      if (refBatchDate != null) 'ref_batch_date': refBatchDate,
      if (refBatchId != null) 'ref_batch_id': refBatchId,
      if (dailyCountSnapshot != null)
        'daily_count_snapshot': dailyCountSnapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyLearningsCompanion copyWith({
    Value<String>? learningDate,
    Value<String>? refBatchDate,
    Value<int>? refBatchId,
    Value<int>? dailyCountSnapshot,
    Value<int>? rowid,
  }) {
    return DailyLearningsCompanion(
      learningDate: learningDate ?? this.learningDate,
      refBatchDate: refBatchDate ?? this.refBatchDate,
      refBatchId: refBatchId ?? this.refBatchId,
      dailyCountSnapshot: dailyCountSnapshot ?? this.dailyCountSnapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (learningDate.present) {
      map['learning_date'] = Variable<String>(learningDate.value);
    }
    if (refBatchDate.present) {
      map['ref_batch_date'] = Variable<String>(refBatchDate.value);
    }
    if (refBatchId.present) {
      map['ref_batch_id'] = Variable<int>(refBatchId.value);
    }
    if (dailyCountSnapshot.present) {
      map['daily_count_snapshot'] = Variable<int>(dailyCountSnapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLearningsCompanion(')
          ..write('learningDate: $learningDate, ')
          ..write('refBatchDate: $refBatchDate, ')
          ..write('refBatchId: $refBatchId, ')
          ..write('dailyCountSnapshot: $dailyCountSnapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ArticlesTable extends Articles
    with TableInfo<$ArticlesTable, ArticleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<int> batchId = GeneratedColumn<int>(
    'batch_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES article_batch (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentCategoryMeta = const VerificationMeta(
    'contentCategory',
  );
  @override
  late final GeneratedColumn<String> contentCategory = GeneratedColumn<String>(
    'content_category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generationStartedAtMeta =
      const VerificationMeta('generationStartedAt');
  @override
  late final GeneratedColumn<String> generationStartedAt =
      GeneratedColumn<String>(
        'generation_started_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _generationCompletedAtMeta =
      const VerificationMeta('generationCompletedAt');
  @override
  late final GeneratedColumn<String> generationCompletedAt =
      GeneratedColumn<String>(
        'generation_completed_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accumulatedReadSecondsMeta =
      const VerificationMeta('accumulatedReadSeconds');
  @override
  late final GeneratedColumn<int> accumulatedReadSeconds = GeneratedColumn<int>(
    'accumulated_read_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readCompletedAtMeta = const VerificationMeta(
    'readCompletedAt',
  );
  @override
  late final GeneratedColumn<String> readCompletedAt = GeneratedColumn<String>(
    'read_completed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRetryAtMeta = const VerificationMeta(
    'lastRetryAt',
  );
  @override
  late final GeneratedColumn<String> lastRetryAt = GeneratedColumn<String>(
    'last_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxRetriesMeta = const VerificationMeta(
    'maxRetries',
  );
  @override
  late final GeneratedColumn<int> maxRetries = GeneratedColumn<int>(
    'max_retries',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<String> nextRetryAt = GeneratedColumn<String>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    batchId,
    orderIndex,
    contentCategory,
    title,
    status,
    generationStartedAt,
    generationCompletedAt,
    retryCount,
    accumulatedReadSeconds,
    readCompletedAt,
    lastRetryAt,
    maxRetries,
    nextRetryAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArticleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_batchIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('content_category')) {
      context.handle(
        _contentCategoryMeta,
        contentCategory.isAcceptableOrUnknown(
          data['content_category']!,
          _contentCategoryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentCategoryMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('generation_started_at')) {
      context.handle(
        _generationStartedAtMeta,
        generationStartedAt.isAcceptableOrUnknown(
          data['generation_started_at']!,
          _generationStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('generation_completed_at')) {
      context.handle(
        _generationCompletedAtMeta,
        generationCompletedAt.isAcceptableOrUnknown(
          data['generation_completed_at']!,
          _generationCompletedAtMeta,
        ),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    } else if (isInserting) {
      context.missing(_retryCountMeta);
    }
    if (data.containsKey('accumulated_read_seconds')) {
      context.handle(
        _accumulatedReadSecondsMeta,
        accumulatedReadSeconds.isAcceptableOrUnknown(
          data['accumulated_read_seconds']!,
          _accumulatedReadSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accumulatedReadSecondsMeta);
    }
    if (data.containsKey('read_completed_at')) {
      context.handle(
        _readCompletedAtMeta,
        readCompletedAt.isAcceptableOrUnknown(
          data['read_completed_at']!,
          _readCompletedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_retry_at')) {
      context.handle(
        _lastRetryAtMeta,
        lastRetryAt.isAcceptableOrUnknown(
          data['last_retry_at']!,
          _lastRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('max_retries')) {
      context.handle(
        _maxRetriesMeta,
        maxRetries.isAcceptableOrUnknown(data['max_retries']!, _maxRetriesMeta),
      );
    } else if (isInserting) {
      context.missing(_maxRetriesMeta);
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArticleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}batch_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      contentCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_category'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      generationStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation_started_at'],
      ),
      generationCompletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation_completed_at'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      accumulatedReadSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accumulated_read_seconds'],
      )!,
      readCompletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}read_completed_at'],
      ),
      lastRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_retry_at'],
      ),
      maxRetries: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_retries'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_retry_at'],
      ),
    );
  }

  @override
  $ArticlesTable createAlias(String alias) {
    return $ArticlesTable(attachedDatabase, alias);
  }
}

class ArticleRow extends DataClass implements Insertable<ArticleRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// Room: ForeignKey(ArticleBatchEntity, parent = id, child = batch_id, onDelete = CASCADE)
  final int batchId;
  final int orderIndex;

  /// 生成时的类别标识（TEXT，值由生成输入决定，无枚举约束）
  final String contentCategory;

  /// populated after generation succeeds
  final String? title;

  /// PENDING | GENERATING | SUCCESS | TIMEOUT | FAILED | FATAL
  final String status;
  final String? generationStartedAt;
  final String? generationCompletedAt;
  final int retryCount;
  final int accumulatedReadSeconds;
  final String? readCompletedAt;
  final String? lastRetryAt;
  final int maxRetries;
  final String? nextRetryAt;
  const ArticleRow({
    required this.id,
    required this.batchId,
    required this.orderIndex,
    required this.contentCategory,
    this.title,
    required this.status,
    this.generationStartedAt,
    this.generationCompletedAt,
    required this.retryCount,
    required this.accumulatedReadSeconds,
    this.readCompletedAt,
    this.lastRetryAt,
    required this.maxRetries,
    this.nextRetryAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['batch_id'] = Variable<int>(batchId);
    map['order_index'] = Variable<int>(orderIndex);
    map['content_category'] = Variable<String>(contentCategory);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || generationStartedAt != null) {
      map['generation_started_at'] = Variable<String>(generationStartedAt);
    }
    if (!nullToAbsent || generationCompletedAt != null) {
      map['generation_completed_at'] = Variable<String>(generationCompletedAt);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['accumulated_read_seconds'] = Variable<int>(accumulatedReadSeconds);
    if (!nullToAbsent || readCompletedAt != null) {
      map['read_completed_at'] = Variable<String>(readCompletedAt);
    }
    if (!nullToAbsent || lastRetryAt != null) {
      map['last_retry_at'] = Variable<String>(lastRetryAt);
    }
    map['max_retries'] = Variable<int>(maxRetries);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<String>(nextRetryAt);
    }
    return map;
  }

  ArticlesCompanion toCompanion(bool nullToAbsent) {
    return ArticlesCompanion(
      id: Value(id),
      batchId: Value(batchId),
      orderIndex: Value(orderIndex),
      contentCategory: Value(contentCategory),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      status: Value(status),
      generationStartedAt: generationStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(generationStartedAt),
      generationCompletedAt: generationCompletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(generationCompletedAt),
      retryCount: Value(retryCount),
      accumulatedReadSeconds: Value(accumulatedReadSeconds),
      readCompletedAt: readCompletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readCompletedAt),
      lastRetryAt: lastRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRetryAt),
      maxRetries: Value(maxRetries),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
    );
  }

  factory ArticleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticleRow(
      id: serializer.fromJson<int>(json['id']),
      batchId: serializer.fromJson<int>(json['batchId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      contentCategory: serializer.fromJson<String>(json['contentCategory']),
      title: serializer.fromJson<String?>(json['title']),
      status: serializer.fromJson<String>(json['status']),
      generationStartedAt: serializer.fromJson<String?>(
        json['generationStartedAt'],
      ),
      generationCompletedAt: serializer.fromJson<String?>(
        json['generationCompletedAt'],
      ),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      accumulatedReadSeconds: serializer.fromJson<int>(
        json['accumulatedReadSeconds'],
      ),
      readCompletedAt: serializer.fromJson<String?>(json['readCompletedAt']),
      lastRetryAt: serializer.fromJson<String?>(json['lastRetryAt']),
      maxRetries: serializer.fromJson<int>(json['maxRetries']),
      nextRetryAt: serializer.fromJson<String?>(json['nextRetryAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'batchId': serializer.toJson<int>(batchId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'contentCategory': serializer.toJson<String>(contentCategory),
      'title': serializer.toJson<String?>(title),
      'status': serializer.toJson<String>(status),
      'generationStartedAt': serializer.toJson<String?>(generationStartedAt),
      'generationCompletedAt': serializer.toJson<String?>(
        generationCompletedAt,
      ),
      'retryCount': serializer.toJson<int>(retryCount),
      'accumulatedReadSeconds': serializer.toJson<int>(accumulatedReadSeconds),
      'readCompletedAt': serializer.toJson<String?>(readCompletedAt),
      'lastRetryAt': serializer.toJson<String?>(lastRetryAt),
      'maxRetries': serializer.toJson<int>(maxRetries),
      'nextRetryAt': serializer.toJson<String?>(nextRetryAt),
    };
  }

  ArticleRow copyWith({
    int? id,
    int? batchId,
    int? orderIndex,
    String? contentCategory,
    Value<String?> title = const Value.absent(),
    String? status,
    Value<String?> generationStartedAt = const Value.absent(),
    Value<String?> generationCompletedAt = const Value.absent(),
    int? retryCount,
    int? accumulatedReadSeconds,
    Value<String?> readCompletedAt = const Value.absent(),
    Value<String?> lastRetryAt = const Value.absent(),
    int? maxRetries,
    Value<String?> nextRetryAt = const Value.absent(),
  }) => ArticleRow(
    id: id ?? this.id,
    batchId: batchId ?? this.batchId,
    orderIndex: orderIndex ?? this.orderIndex,
    contentCategory: contentCategory ?? this.contentCategory,
    title: title.present ? title.value : this.title,
    status: status ?? this.status,
    generationStartedAt: generationStartedAt.present
        ? generationStartedAt.value
        : this.generationStartedAt,
    generationCompletedAt: generationCompletedAt.present
        ? generationCompletedAt.value
        : this.generationCompletedAt,
    retryCount: retryCount ?? this.retryCount,
    accumulatedReadSeconds:
        accumulatedReadSeconds ?? this.accumulatedReadSeconds,
    readCompletedAt: readCompletedAt.present
        ? readCompletedAt.value
        : this.readCompletedAt,
    lastRetryAt: lastRetryAt.present ? lastRetryAt.value : this.lastRetryAt,
    maxRetries: maxRetries ?? this.maxRetries,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
  );
  ArticleRow copyWithCompanion(ArticlesCompanion data) {
    return ArticleRow(
      id: data.id.present ? data.id.value : this.id,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      contentCategory: data.contentCategory.present
          ? data.contentCategory.value
          : this.contentCategory,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      generationStartedAt: data.generationStartedAt.present
          ? data.generationStartedAt.value
          : this.generationStartedAt,
      generationCompletedAt: data.generationCompletedAt.present
          ? data.generationCompletedAt.value
          : this.generationCompletedAt,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      accumulatedReadSeconds: data.accumulatedReadSeconds.present
          ? data.accumulatedReadSeconds.value
          : this.accumulatedReadSeconds,
      readCompletedAt: data.readCompletedAt.present
          ? data.readCompletedAt.value
          : this.readCompletedAt,
      lastRetryAt: data.lastRetryAt.present
          ? data.lastRetryAt.value
          : this.lastRetryAt,
      maxRetries: data.maxRetries.present
          ? data.maxRetries.value
          : this.maxRetries,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticleRow(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('contentCategory: $contentCategory, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('generationStartedAt: $generationStartedAt, ')
          ..write('generationCompletedAt: $generationCompletedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('accumulatedReadSeconds: $accumulatedReadSeconds, ')
          ..write('readCompletedAt: $readCompletedAt, ')
          ..write('lastRetryAt: $lastRetryAt, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('nextRetryAt: $nextRetryAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    batchId,
    orderIndex,
    contentCategory,
    title,
    status,
    generationStartedAt,
    generationCompletedAt,
    retryCount,
    accumulatedReadSeconds,
    readCompletedAt,
    lastRetryAt,
    maxRetries,
    nextRetryAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticleRow &&
          other.id == this.id &&
          other.batchId == this.batchId &&
          other.orderIndex == this.orderIndex &&
          other.contentCategory == this.contentCategory &&
          other.title == this.title &&
          other.status == this.status &&
          other.generationStartedAt == this.generationStartedAt &&
          other.generationCompletedAt == this.generationCompletedAt &&
          other.retryCount == this.retryCount &&
          other.accumulatedReadSeconds == this.accumulatedReadSeconds &&
          other.readCompletedAt == this.readCompletedAt &&
          other.lastRetryAt == this.lastRetryAt &&
          other.maxRetries == this.maxRetries &&
          other.nextRetryAt == this.nextRetryAt);
}

class ArticlesCompanion extends UpdateCompanion<ArticleRow> {
  final Value<int> id;
  final Value<int> batchId;
  final Value<int> orderIndex;
  final Value<String> contentCategory;
  final Value<String?> title;
  final Value<String> status;
  final Value<String?> generationStartedAt;
  final Value<String?> generationCompletedAt;
  final Value<int> retryCount;
  final Value<int> accumulatedReadSeconds;
  final Value<String?> readCompletedAt;
  final Value<String?> lastRetryAt;
  final Value<int> maxRetries;
  final Value<String?> nextRetryAt;
  const ArticlesCompanion({
    this.id = const Value.absent(),
    this.batchId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.contentCategory = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.generationStartedAt = const Value.absent(),
    this.generationCompletedAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.accumulatedReadSeconds = const Value.absent(),
    this.readCompletedAt = const Value.absent(),
    this.lastRetryAt = const Value.absent(),
    this.maxRetries = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
  });
  ArticlesCompanion.insert({
    this.id = const Value.absent(),
    required int batchId,
    required int orderIndex,
    required String contentCategory,
    this.title = const Value.absent(),
    required String status,
    this.generationStartedAt = const Value.absent(),
    this.generationCompletedAt = const Value.absent(),
    required int retryCount,
    required int accumulatedReadSeconds,
    this.readCompletedAt = const Value.absent(),
    this.lastRetryAt = const Value.absent(),
    required int maxRetries,
    this.nextRetryAt = const Value.absent(),
  }) : batchId = Value(batchId),
       orderIndex = Value(orderIndex),
       contentCategory = Value(contentCategory),
       status = Value(status),
       retryCount = Value(retryCount),
       accumulatedReadSeconds = Value(accumulatedReadSeconds),
       maxRetries = Value(maxRetries);
  static Insertable<ArticleRow> custom({
    Expression<int>? id,
    Expression<int>? batchId,
    Expression<int>? orderIndex,
    Expression<String>? contentCategory,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? generationStartedAt,
    Expression<String>? generationCompletedAt,
    Expression<int>? retryCount,
    Expression<int>? accumulatedReadSeconds,
    Expression<String>? readCompletedAt,
    Expression<String>? lastRetryAt,
    Expression<int>? maxRetries,
    Expression<String>? nextRetryAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (batchId != null) 'batch_id': batchId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (contentCategory != null) 'content_category': contentCategory,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (generationStartedAt != null)
        'generation_started_at': generationStartedAt,
      if (generationCompletedAt != null)
        'generation_completed_at': generationCompletedAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (accumulatedReadSeconds != null)
        'accumulated_read_seconds': accumulatedReadSeconds,
      if (readCompletedAt != null) 'read_completed_at': readCompletedAt,
      if (lastRetryAt != null) 'last_retry_at': lastRetryAt,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
    });
  }

  ArticlesCompanion copyWith({
    Value<int>? id,
    Value<int>? batchId,
    Value<int>? orderIndex,
    Value<String>? contentCategory,
    Value<String?>? title,
    Value<String>? status,
    Value<String?>? generationStartedAt,
    Value<String?>? generationCompletedAt,
    Value<int>? retryCount,
    Value<int>? accumulatedReadSeconds,
    Value<String?>? readCompletedAt,
    Value<String?>? lastRetryAt,
    Value<int>? maxRetries,
    Value<String?>? nextRetryAt,
  }) {
    return ArticlesCompanion(
      id: id ?? this.id,
      batchId: batchId ?? this.batchId,
      orderIndex: orderIndex ?? this.orderIndex,
      contentCategory: contentCategory ?? this.contentCategory,
      title: title ?? this.title,
      status: status ?? this.status,
      generationStartedAt: generationStartedAt ?? this.generationStartedAt,
      generationCompletedAt:
          generationCompletedAt ?? this.generationCompletedAt,
      retryCount: retryCount ?? this.retryCount,
      accumulatedReadSeconds:
          accumulatedReadSeconds ?? this.accumulatedReadSeconds,
      readCompletedAt: readCompletedAt ?? this.readCompletedAt,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      maxRetries: maxRetries ?? this.maxRetries,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<int>(batchId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (contentCategory.present) {
      map['content_category'] = Variable<String>(contentCategory.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (generationStartedAt.present) {
      map['generation_started_at'] = Variable<String>(
        generationStartedAt.value,
      );
    }
    if (generationCompletedAt.present) {
      map['generation_completed_at'] = Variable<String>(
        generationCompletedAt.value,
      );
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (accumulatedReadSeconds.present) {
      map['accumulated_read_seconds'] = Variable<int>(
        accumulatedReadSeconds.value,
      );
    }
    if (readCompletedAt.present) {
      map['read_completed_at'] = Variable<String>(readCompletedAt.value);
    }
    if (lastRetryAt.present) {
      map['last_retry_at'] = Variable<String>(lastRetryAt.value);
    }
    if (maxRetries.present) {
      map['max_retries'] = Variable<int>(maxRetries.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<String>(nextRetryAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticlesCompanion(')
          ..write('id: $id, ')
          ..write('batchId: $batchId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('contentCategory: $contentCategory, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('generationStartedAt: $generationStartedAt, ')
          ..write('generationCompletedAt: $generationCompletedAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('accumulatedReadSeconds: $accumulatedReadSeconds, ')
          ..write('readCompletedAt: $readCompletedAt, ')
          ..write('lastRetryAt: $lastRetryAt, ')
          ..write('maxRetries: $maxRetries, ')
          ..write('nextRetryAt: $nextRetryAt')
          ..write(')'))
        .toString();
  }
}

class $ArticleParagraphsTable extends ArticleParagraphs
    with TableInfo<$ArticleParagraphsTable, ArticleParagraphRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ArticleParagraphsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _articleIdMeta = const VerificationMeta(
    'articleId',
  );
  @override
  late final GeneratedColumn<int> articleId = GeneratedColumn<int>(
    'article_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES article (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _orderIndexMeta = const VerificationMeta(
    'orderIndex',
  );
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
    'order_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _englishTextMeta = const VerificationMeta(
    'englishText',
  );
  @override
  late final GeneratedColumn<String> englishText = GeneratedColumn<String>(
    'english_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chineseTranslationMeta =
      const VerificationMeta('chineseTranslation');
  @override
  late final GeneratedColumn<String> chineseTranslation =
      GeneratedColumn<String>(
        'chinese_translation',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    articleId,
    orderIndex,
    englishText,
    chineseTranslation,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'article_paragraph';
  @override
  VerificationContext validateIntegrity(
    Insertable<ArticleParagraphRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('article_id')) {
      context.handle(
        _articleIdMeta,
        articleId.isAcceptableOrUnknown(data['article_id']!, _articleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_articleIdMeta);
    }
    if (data.containsKey('order_index')) {
      context.handle(
        _orderIndexMeta,
        orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('english_text')) {
      context.handle(
        _englishTextMeta,
        englishText.isAcceptableOrUnknown(
          data['english_text']!,
          _englishTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_englishTextMeta);
    }
    if (data.containsKey('chinese_translation')) {
      context.handle(
        _chineseTranslationMeta,
        chineseTranslation.isAcceptableOrUnknown(
          data['chinese_translation']!,
          _chineseTranslationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chineseTranslationMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ArticleParagraphRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ArticleParagraphRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      articleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}article_id'],
      )!,
      orderIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_index'],
      )!,
      englishText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}english_text'],
      )!,
      chineseTranslation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chinese_translation'],
      )!,
    );
  }

  @override
  $ArticleParagraphsTable createAlias(String alias) {
    return $ArticleParagraphsTable(attachedDatabase, alias);
  }
}

class ArticleParagraphRow extends DataClass
    implements Insertable<ArticleParagraphRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// Room: ForeignKey(ArticleEntity, parent = id, child = article_id, onDelete = CASCADE)
  final int articleId;
  final int orderIndex;
  final String englishText;
  final String chineseTranslation;
  const ArticleParagraphRow({
    required this.id,
    required this.articleId,
    required this.orderIndex,
    required this.englishText,
    required this.chineseTranslation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['article_id'] = Variable<int>(articleId);
    map['order_index'] = Variable<int>(orderIndex);
    map['english_text'] = Variable<String>(englishText);
    map['chinese_translation'] = Variable<String>(chineseTranslation);
    return map;
  }

  ArticleParagraphsCompanion toCompanion(bool nullToAbsent) {
    return ArticleParagraphsCompanion(
      id: Value(id),
      articleId: Value(articleId),
      orderIndex: Value(orderIndex),
      englishText: Value(englishText),
      chineseTranslation: Value(chineseTranslation),
    );
  }

  factory ArticleParagraphRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ArticleParagraphRow(
      id: serializer.fromJson<int>(json['id']),
      articleId: serializer.fromJson<int>(json['articleId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      englishText: serializer.fromJson<String>(json['englishText']),
      chineseTranslation: serializer.fromJson<String>(
        json['chineseTranslation'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'articleId': serializer.toJson<int>(articleId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'englishText': serializer.toJson<String>(englishText),
      'chineseTranslation': serializer.toJson<String>(chineseTranslation),
    };
  }

  ArticleParagraphRow copyWith({
    int? id,
    int? articleId,
    int? orderIndex,
    String? englishText,
    String? chineseTranslation,
  }) => ArticleParagraphRow(
    id: id ?? this.id,
    articleId: articleId ?? this.articleId,
    orderIndex: orderIndex ?? this.orderIndex,
    englishText: englishText ?? this.englishText,
    chineseTranslation: chineseTranslation ?? this.chineseTranslation,
  );
  ArticleParagraphRow copyWithCompanion(ArticleParagraphsCompanion data) {
    return ArticleParagraphRow(
      id: data.id.present ? data.id.value : this.id,
      articleId: data.articleId.present ? data.articleId.value : this.articleId,
      orderIndex: data.orderIndex.present
          ? data.orderIndex.value
          : this.orderIndex,
      englishText: data.englishText.present
          ? data.englishText.value
          : this.englishText,
      chineseTranslation: data.chineseTranslation.present
          ? data.chineseTranslation.value
          : this.chineseTranslation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ArticleParagraphRow(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('englishText: $englishText, ')
          ..write('chineseTranslation: $chineseTranslation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, articleId, orderIndex, englishText, chineseTranslation);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ArticleParagraphRow &&
          other.id == this.id &&
          other.articleId == this.articleId &&
          other.orderIndex == this.orderIndex &&
          other.englishText == this.englishText &&
          other.chineseTranslation == this.chineseTranslation);
}

class ArticleParagraphsCompanion extends UpdateCompanion<ArticleParagraphRow> {
  final Value<int> id;
  final Value<int> articleId;
  final Value<int> orderIndex;
  final Value<String> englishText;
  final Value<String> chineseTranslation;
  const ArticleParagraphsCompanion({
    this.id = const Value.absent(),
    this.articleId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.englishText = const Value.absent(),
    this.chineseTranslation = const Value.absent(),
  });
  ArticleParagraphsCompanion.insert({
    this.id = const Value.absent(),
    required int articleId,
    required int orderIndex,
    required String englishText,
    required String chineseTranslation,
  }) : articleId = Value(articleId),
       orderIndex = Value(orderIndex),
       englishText = Value(englishText),
       chineseTranslation = Value(chineseTranslation);
  static Insertable<ArticleParagraphRow> custom({
    Expression<int>? id,
    Expression<int>? articleId,
    Expression<int>? orderIndex,
    Expression<String>? englishText,
    Expression<String>? chineseTranslation,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (articleId != null) 'article_id': articleId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (englishText != null) 'english_text': englishText,
      if (chineseTranslation != null) 'chinese_translation': chineseTranslation,
    });
  }

  ArticleParagraphsCompanion copyWith({
    Value<int>? id,
    Value<int>? articleId,
    Value<int>? orderIndex,
    Value<String>? englishText,
    Value<String>? chineseTranslation,
  }) {
    return ArticleParagraphsCompanion(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      orderIndex: orderIndex ?? this.orderIndex,
      englishText: englishText ?? this.englishText,
      chineseTranslation: chineseTranslation ?? this.chineseTranslation,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (articleId.present) {
      map['article_id'] = Variable<int>(articleId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (englishText.present) {
      map['english_text'] = Variable<String>(englishText.value);
    }
    if (chineseTranslation.present) {
      map['chinese_translation'] = Variable<String>(chineseTranslation.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ArticleParagraphsCompanion(')
          ..write('id: $id, ')
          ..write('articleId: $articleId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('englishText: $englishText, ')
          ..write('chineseTranslation: $chineseTranslation')
          ..write(')'))
        .toString();
  }
}

class $GenerationErrorLogsTable extends GenerationErrorLogs
    with TableInfo<$GenerationErrorLogsTable, GenerationErrorLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GenerationErrorLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<int> entityId = GeneratedColumn<int>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorHelpMeta = const VerificationMeta(
    'errorHelp',
  );
  @override
  late final GeneratedColumn<String> errorHelp = GeneratedColumn<String>(
    'error_help',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notifiedAtMeta = const VerificationMeta(
    'notifiedAt',
  );
  @override
  late final GeneratedColumn<int> notifiedAt = GeneratedColumn<int>(
    'notified_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    errorCode,
    errorMessage,
    errorHelp,
    retryCount,
    createdAt,
    notifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'generation_error_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<GenerationErrorLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_errorCodeMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_errorMessageMeta);
    }
    if (data.containsKey('error_help')) {
      context.handle(
        _errorHelpMeta,
        errorHelp.isAcceptableOrUnknown(data['error_help']!, _errorHelpMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    } else if (isInserting) {
      context.missing(_retryCountMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('notified_at')) {
      context.handle(
        _notifiedAtMeta,
        notifiedAt.isAcceptableOrUnknown(data['notified_at']!, _notifiedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GenerationErrorLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GenerationErrorLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entity_id'],
      )!,
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      )!,
      errorHelp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_help'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      notifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notified_at'],
      ),
    );
  }

  @override
  $GenerationErrorLogsTable createAlias(String alias) {
    return $GenerationErrorLogsTable(attachedDatabase, alias);
  }
}

class GenerationErrorLogRow extends DataClass
    implements Insertable<GenerationErrorLogRow> {
  /// Room: @PrimaryKey(autoGenerate = true) val id: Long
  final int id;

  /// "BATCH" | "ARTICLE"
  final String entityType;
  final int entityId;
  final String errorCode;
  final String errorMessage;
  final String? errorHelp;

  /// 快照：错误发生时的重试次数
  final int retryCount;
  final String createdAt;

  /// 飞书告警送达时间（Unix millis）；null = 未通知，启动时补发
  final int? notifiedAt;
  const GenerationErrorLogRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.errorCode,
    required this.errorMessage,
    this.errorHelp,
    required this.retryCount,
    required this.createdAt,
    this.notifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<int>(entityId);
    map['error_code'] = Variable<String>(errorCode);
    map['error_message'] = Variable<String>(errorMessage);
    if (!nullToAbsent || errorHelp != null) {
      map['error_help'] = Variable<String>(errorHelp);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || notifiedAt != null) {
      map['notified_at'] = Variable<int>(notifiedAt);
    }
    return map;
  }

  GenerationErrorLogsCompanion toCompanion(bool nullToAbsent) {
    return GenerationErrorLogsCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      errorCode: Value(errorCode),
      errorMessage: Value(errorMessage),
      errorHelp: errorHelp == null && nullToAbsent
          ? const Value.absent()
          : Value(errorHelp),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
      notifiedAt: notifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(notifiedAt),
    );
  }

  factory GenerationErrorLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GenerationErrorLogRow(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<int>(json['entityId']),
      errorCode: serializer.fromJson<String>(json['errorCode']),
      errorMessage: serializer.fromJson<String>(json['errorMessage']),
      errorHelp: serializer.fromJson<String?>(json['errorHelp']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      notifiedAt: serializer.fromJson<int?>(json['notifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<int>(entityId),
      'errorCode': serializer.toJson<String>(errorCode),
      'errorMessage': serializer.toJson<String>(errorMessage),
      'errorHelp': serializer.toJson<String?>(errorHelp),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<String>(createdAt),
      'notifiedAt': serializer.toJson<int?>(notifiedAt),
    };
  }

  GenerationErrorLogRow copyWith({
    int? id,
    String? entityType,
    int? entityId,
    String? errorCode,
    String? errorMessage,
    Value<String?> errorHelp = const Value.absent(),
    int? retryCount,
    String? createdAt,
    Value<int?> notifiedAt = const Value.absent(),
  }) => GenerationErrorLogRow(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    errorCode: errorCode ?? this.errorCode,
    errorMessage: errorMessage ?? this.errorMessage,
    errorHelp: errorHelp.present ? errorHelp.value : this.errorHelp,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
    notifiedAt: notifiedAt.present ? notifiedAt.value : this.notifiedAt,
  );
  GenerationErrorLogRow copyWithCompanion(GenerationErrorLogsCompanion data) {
    return GenerationErrorLogRow(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      errorHelp: data.errorHelp.present ? data.errorHelp.value : this.errorHelp,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      notifiedAt: data.notifiedAt.present
          ? data.notifiedAt.value
          : this.notifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GenerationErrorLogRow(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('errorHelp: $errorHelp, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('notifiedAt: $notifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    errorCode,
    errorMessage,
    errorHelp,
    retryCount,
    createdAt,
    notifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GenerationErrorLogRow &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.errorCode == this.errorCode &&
          other.errorMessage == this.errorMessage &&
          other.errorHelp == this.errorHelp &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt &&
          other.notifiedAt == this.notifiedAt);
}

class GenerationErrorLogsCompanion
    extends UpdateCompanion<GenerationErrorLogRow> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<int> entityId;
  final Value<String> errorCode;
  final Value<String> errorMessage;
  final Value<String?> errorHelp;
  final Value<int> retryCount;
  final Value<String> createdAt;
  final Value<int?> notifiedAt;
  const GenerationErrorLogsCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.errorHelp = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.notifiedAt = const Value.absent(),
  });
  GenerationErrorLogsCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required int entityId,
    required String errorCode,
    required String errorMessage,
    this.errorHelp = const Value.absent(),
    required int retryCount,
    required String createdAt,
    this.notifiedAt = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       errorCode = Value(errorCode),
       errorMessage = Value(errorMessage),
       retryCount = Value(retryCount),
       createdAt = Value(createdAt);
  static Insertable<GenerationErrorLogRow> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<int>? entityId,
    Expression<String>? errorCode,
    Expression<String>? errorMessage,
    Expression<String>? errorHelp,
    Expression<int>? retryCount,
    Expression<String>? createdAt,
    Expression<int>? notifiedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (errorHelp != null) 'error_help': errorHelp,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (notifiedAt != null) 'notified_at': notifiedAt,
    });
  }

  GenerationErrorLogsCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<int>? entityId,
    Value<String>? errorCode,
    Value<String>? errorMessage,
    Value<String?>? errorHelp,
    Value<int>? retryCount,
    Value<String>? createdAt,
    Value<int?>? notifiedAt,
  }) {
    return GenerationErrorLogsCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      errorCode: errorCode ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      errorHelp: errorHelp ?? this.errorHelp,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      notifiedAt: notifiedAt ?? this.notifiedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<int>(entityId.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (errorHelp.present) {
      map['error_help'] = Variable<String>(errorHelp.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (notifiedAt.present) {
      map['notified_at'] = Variable<int>(notifiedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GenerationErrorLogsCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('errorCode: $errorCode, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('errorHelp: $errorHelp, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('notifiedAt: $notifiedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final $ConfigChangeLogsTable configChangeLogs = $ConfigChangeLogsTable(
    this,
  );
  late final $SchemaMigrationLogsTable schemaMigrationLogs =
      $SchemaMigrationLogsTable(this);
  late final $GenerationPipelineStatusesTable generationPipelineStatuses =
      $GenerationPipelineStatusesTable(this);
  late final $DailyLearningLogsTable dailyLearningLogs =
      $DailyLearningLogsTable(this);
  late final $LearningStatsSummariesTable learningStatsSummaries =
      $LearningStatsSummariesTable(this);
  late final $ArticleBatchesTable articleBatches = $ArticleBatchesTable(this);
  late final $DailyLearningsTable dailyLearnings = $DailyLearningsTable(this);
  late final $ArticlesTable articles = $ArticlesTable(this);
  late final $ArticleParagraphsTable articleParagraphs =
      $ArticleParagraphsTable(this);
  late final $GenerationErrorLogsTable generationErrorLogs =
      $GenerationErrorLogsTable(this);
  late final Index indexDailyLearningRefBatchId = Index(
    'index_daily_learning_ref_batch_id',
    'CREATE INDEX index_daily_learning_ref_batch_id ON daily_learning (ref_batch_id)',
  );
  late final Index indexArticleBatchGeneratedOn = Index(
    'index_article_batch_generated_on',
    'CREATE INDEX index_article_batch_generated_on ON article_batch (generated_on)',
  );
  late final Index indexArticleBatchDifficultyLevelSnapshotGeneratedOn = Index(
    'index_article_batch_difficulty_level_snapshot_generated_on',
    'CREATE UNIQUE INDEX index_article_batch_difficulty_level_snapshot_generated_on ON article_batch (difficulty_level_snapshot, generated_on)',
  );
  late final Index indexArticleBatchId = Index(
    'index_article_batch_id',
    'CREATE INDEX index_article_batch_id ON article (batch_id)',
  );
  late final Index indexArticleParagraphArticleId = Index(
    'index_article_paragraph_article_id',
    'CREATE INDEX index_article_paragraph_article_id ON article_paragraph (article_id)',
  );
  late final Index indexArticleParagraphArticleIdOrderIndex = Index(
    'index_article_paragraph_article_id_order_index',
    'CREATE UNIQUE INDEX index_article_paragraph_article_id_order_index ON article_paragraph (article_id, order_index)',
  );
  late final Index indexGenerationErrorLogEntityTypeEntityId = Index(
    'index_generation_error_log_entity_type_entity_id',
    'CREATE INDEX index_generation_error_log_entity_type_entity_id ON generation_error_log (entity_type, entity_id)',
  );
  late final Index indexGenerationErrorLogCreatedAt = Index(
    'index_generation_error_log_created_at',
    'CREATE INDEX index_generation_error_log_created_at ON generation_error_log (created_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    userSettings,
    configChangeLogs,
    schemaMigrationLogs,
    generationPipelineStatuses,
    dailyLearningLogs,
    learningStatsSummaries,
    articleBatches,
    dailyLearnings,
    articles,
    articleParagraphs,
    generationErrorLogs,
    indexDailyLearningRefBatchId,
    indexArticleBatchGeneratedOn,
    indexArticleBatchDifficultyLevelSnapshotGeneratedOn,
    indexArticleBatchId,
    indexArticleParagraphArticleId,
    indexArticleParagraphArticleIdOrderIndex,
    indexGenerationErrorLogEntityTypeEntityId,
    indexGenerationErrorLogCreatedAt,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'article_batch',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('daily_learning', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'article_batch',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('article', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'article',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('article_paragraph', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<int> id,
      required bool isOnboarded,
      required String difficultyLevel,
      required int dailyArticleCount,
      required String translationDisplayMode,
      required int masteryThresholdN,
      required bool autoPlayAudio,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<int> id,
      Value<bool> isOnboarded,
      Value<String> difficultyLevel,
      Value<int> dailyArticleCount,
      Value<String> translationDisplayMode,
      Value<int> masteryThresholdN,
      Value<bool> autoPlayAudio,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOnboarded => $composableBuilder(
    column: $table.isOnboarded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get difficultyLevel => $composableBuilder(
    column: $table.difficultyLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyArticleCount => $composableBuilder(
    column: $table.dailyArticleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get translationDisplayMode => $composableBuilder(
    column: $table.translationDisplayMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get masteryThresholdN => $composableBuilder(
    column: $table.masteryThresholdN,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoPlayAudio => $composableBuilder(
    column: $table.autoPlayAudio,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOnboarded => $composableBuilder(
    column: $table.isOnboarded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get difficultyLevel => $composableBuilder(
    column: $table.difficultyLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyArticleCount => $composableBuilder(
    column: $table.dailyArticleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get translationDisplayMode => $composableBuilder(
    column: $table.translationDisplayMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get masteryThresholdN => $composableBuilder(
    column: $table.masteryThresholdN,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoPlayAudio => $composableBuilder(
    column: $table.autoPlayAudio,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isOnboarded => $composableBuilder(
    column: $table.isOnboarded,
    builder: (column) => column,
  );

  GeneratedColumn<String> get difficultyLevel => $composableBuilder(
    column: $table.difficultyLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dailyArticleCount => $composableBuilder(
    column: $table.dailyArticleCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get translationDisplayMode => $composableBuilder(
    column: $table.translationDisplayMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get masteryThresholdN => $composableBuilder(
    column: $table.masteryThresholdN,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoPlayAudio => $composableBuilder(
    column: $table.autoPlayAudio,
    builder: (column) => column,
  );
}

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          UserSettingsRow,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            UserSettingsRow,
            BaseReferences<_$AppDatabase, $UserSettingsTable, UserSettingsRow>,
          ),
          UserSettingsRow,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isOnboarded = const Value.absent(),
                Value<String> difficultyLevel = const Value.absent(),
                Value<int> dailyArticleCount = const Value.absent(),
                Value<String> translationDisplayMode = const Value.absent(),
                Value<int> masteryThresholdN = const Value.absent(),
                Value<bool> autoPlayAudio = const Value.absent(),
              }) => UserSettingsCompanion(
                id: id,
                isOnboarded: isOnboarded,
                difficultyLevel: difficultyLevel,
                dailyArticleCount: dailyArticleCount,
                translationDisplayMode: translationDisplayMode,
                masteryThresholdN: masteryThresholdN,
                autoPlayAudio: autoPlayAudio,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required bool isOnboarded,
                required String difficultyLevel,
                required int dailyArticleCount,
                required String translationDisplayMode,
                required int masteryThresholdN,
                required bool autoPlayAudio,
              }) => UserSettingsCompanion.insert(
                id: id,
                isOnboarded: isOnboarded,
                difficultyLevel: difficultyLevel,
                dailyArticleCount: dailyArticleCount,
                translationDisplayMode: translationDisplayMode,
                masteryThresholdN: masteryThresholdN,
                autoPlayAudio: autoPlayAudio,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      UserSettingsRow,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (
        UserSettingsRow,
        BaseReferences<_$AppDatabase, $UserSettingsTable, UserSettingsRow>,
      ),
      UserSettingsRow,
      PrefetchHooks Function()
    >;
typedef $$ConfigChangeLogsTableCreateCompanionBuilder =
    ConfigChangeLogsCompanion Function({
      Value<int> id,
      required String fieldName,
      required String oldValue,
      required String newValue,
      required String createdAt,
    });
typedef $$ConfigChangeLogsTableUpdateCompanionBuilder =
    ConfigChangeLogsCompanion Function({
      Value<int> id,
      Value<String> fieldName,
      Value<String> oldValue,
      Value<String> newValue,
      Value<String> createdAt,
    });

class $$ConfigChangeLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ConfigChangeLogsTable> {
  $$ConfigChangeLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldName => $composableBuilder(
    column: $table.fieldName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oldValue => $composableBuilder(
    column: $table.oldValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newValue => $composableBuilder(
    column: $table.newValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConfigChangeLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConfigChangeLogsTable> {
  $$ConfigChangeLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldName => $composableBuilder(
    column: $table.fieldName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oldValue => $composableBuilder(
    column: $table.oldValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newValue => $composableBuilder(
    column: $table.newValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConfigChangeLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConfigChangeLogsTable> {
  $$ConfigChangeLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fieldName =>
      $composableBuilder(column: $table.fieldName, builder: (column) => column);

  GeneratedColumn<String> get oldValue =>
      $composableBuilder(column: $table.oldValue, builder: (column) => column);

  GeneratedColumn<String> get newValue =>
      $composableBuilder(column: $table.newValue, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ConfigChangeLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConfigChangeLogsTable,
          ConfigChangeLogRow,
          $$ConfigChangeLogsTableFilterComposer,
          $$ConfigChangeLogsTableOrderingComposer,
          $$ConfigChangeLogsTableAnnotationComposer,
          $$ConfigChangeLogsTableCreateCompanionBuilder,
          $$ConfigChangeLogsTableUpdateCompanionBuilder,
          (
            ConfigChangeLogRow,
            BaseReferences<
              _$AppDatabase,
              $ConfigChangeLogsTable,
              ConfigChangeLogRow
            >,
          ),
          ConfigChangeLogRow,
          PrefetchHooks Function()
        > {
  $$ConfigChangeLogsTableTableManager(
    _$AppDatabase db,
    $ConfigChangeLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConfigChangeLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConfigChangeLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConfigChangeLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> fieldName = const Value.absent(),
                Value<String> oldValue = const Value.absent(),
                Value<String> newValue = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => ConfigChangeLogsCompanion(
                id: id,
                fieldName: fieldName,
                oldValue: oldValue,
                newValue: newValue,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String fieldName,
                required String oldValue,
                required String newValue,
                required String createdAt,
              }) => ConfigChangeLogsCompanion.insert(
                id: id,
                fieldName: fieldName,
                oldValue: oldValue,
                newValue: newValue,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConfigChangeLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConfigChangeLogsTable,
      ConfigChangeLogRow,
      $$ConfigChangeLogsTableFilterComposer,
      $$ConfigChangeLogsTableOrderingComposer,
      $$ConfigChangeLogsTableAnnotationComposer,
      $$ConfigChangeLogsTableCreateCompanionBuilder,
      $$ConfigChangeLogsTableUpdateCompanionBuilder,
      (
        ConfigChangeLogRow,
        BaseReferences<
          _$AppDatabase,
          $ConfigChangeLogsTable,
          ConfigChangeLogRow
        >,
      ),
      ConfigChangeLogRow,
      PrefetchHooks Function()
    >;
typedef $$SchemaMigrationLogsTableCreateCompanionBuilder =
    SchemaMigrationLogsCompanion Function({
      Value<int> id,
      required int fromVersion,
      required int toVersion,
      required String description,
      required String createdAt,
    });
typedef $$SchemaMigrationLogsTableUpdateCompanionBuilder =
    SchemaMigrationLogsCompanion Function({
      Value<int> id,
      Value<int> fromVersion,
      Value<int> toVersion,
      Value<String> description,
      Value<String> createdAt,
    });

class $$SchemaMigrationLogsTableFilterComposer
    extends Composer<_$AppDatabase, $SchemaMigrationLogsTable> {
  $$SchemaMigrationLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fromVersion => $composableBuilder(
    column: $table.fromVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toVersion => $composableBuilder(
    column: $table.toVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SchemaMigrationLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $SchemaMigrationLogsTable> {
  $$SchemaMigrationLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fromVersion => $composableBuilder(
    column: $table.fromVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toVersion => $composableBuilder(
    column: $table.toVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SchemaMigrationLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchemaMigrationLogsTable> {
  $$SchemaMigrationLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get fromVersion => $composableBuilder(
    column: $table.fromVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get toVersion =>
      $composableBuilder(column: $table.toVersion, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SchemaMigrationLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchemaMigrationLogsTable,
          SchemaMigrationLogRow,
          $$SchemaMigrationLogsTableFilterComposer,
          $$SchemaMigrationLogsTableOrderingComposer,
          $$SchemaMigrationLogsTableAnnotationComposer,
          $$SchemaMigrationLogsTableCreateCompanionBuilder,
          $$SchemaMigrationLogsTableUpdateCompanionBuilder,
          (
            SchemaMigrationLogRow,
            BaseReferences<
              _$AppDatabase,
              $SchemaMigrationLogsTable,
              SchemaMigrationLogRow
            >,
          ),
          SchemaMigrationLogRow,
          PrefetchHooks Function()
        > {
  $$SchemaMigrationLogsTableTableManager(
    _$AppDatabase db,
    $SchemaMigrationLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchemaMigrationLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchemaMigrationLogsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SchemaMigrationLogsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fromVersion = const Value.absent(),
                Value<int> toVersion = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => SchemaMigrationLogsCompanion(
                id: id,
                fromVersion: fromVersion,
                toVersion: toVersion,
                description: description,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fromVersion,
                required int toVersion,
                required String description,
                required String createdAt,
              }) => SchemaMigrationLogsCompanion.insert(
                id: id,
                fromVersion: fromVersion,
                toVersion: toVersion,
                description: description,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SchemaMigrationLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchemaMigrationLogsTable,
      SchemaMigrationLogRow,
      $$SchemaMigrationLogsTableFilterComposer,
      $$SchemaMigrationLogsTableOrderingComposer,
      $$SchemaMigrationLogsTableAnnotationComposer,
      $$SchemaMigrationLogsTableCreateCompanionBuilder,
      $$SchemaMigrationLogsTableUpdateCompanionBuilder,
      (
        SchemaMigrationLogRow,
        BaseReferences<
          _$AppDatabase,
          $SchemaMigrationLogsTable,
          SchemaMigrationLogRow
        >,
      ),
      SchemaMigrationLogRow,
      PrefetchHooks Function()
    >;
typedef $$GenerationPipelineStatusesTableCreateCompanionBuilder =
    GenerationPipelineStatusesCompanion Function({
      Value<int> id,
      required bool isBlocked,
      Value<String?> blockedReason,
      Value<String?> blockedAt,
      Value<int?> blockedAppVersionCode,
    });
typedef $$GenerationPipelineStatusesTableUpdateCompanionBuilder =
    GenerationPipelineStatusesCompanion Function({
      Value<int> id,
      Value<bool> isBlocked,
      Value<String?> blockedReason,
      Value<String?> blockedAt,
      Value<int?> blockedAppVersionCode,
    });

class $$GenerationPipelineStatusesTableFilterComposer
    extends Composer<_$AppDatabase, $GenerationPipelineStatusesTable> {
  $$GenerationPipelineStatusesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get blockedAppVersionCode => $composableBuilder(
    column: $table.blockedAppVersionCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GenerationPipelineStatusesTableOrderingComposer
    extends Composer<_$AppDatabase, $GenerationPipelineStatusesTable> {
  $$GenerationPipelineStatusesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBlocked => $composableBuilder(
    column: $table.isBlocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get blockedAppVersionCode => $composableBuilder(
    column: $table.blockedAppVersionCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GenerationPipelineStatusesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GenerationPipelineStatusesTable> {
  $$GenerationPipelineStatusesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get isBlocked =>
      $composableBuilder(column: $table.isBlocked, builder: (column) => column);

  GeneratedColumn<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blockedAt =>
      $composableBuilder(column: $table.blockedAt, builder: (column) => column);

  GeneratedColumn<int> get blockedAppVersionCode => $composableBuilder(
    column: $table.blockedAppVersionCode,
    builder: (column) => column,
  );
}

class $$GenerationPipelineStatusesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GenerationPipelineStatusesTable,
          GenerationPipelineStatusRow,
          $$GenerationPipelineStatusesTableFilterComposer,
          $$GenerationPipelineStatusesTableOrderingComposer,
          $$GenerationPipelineStatusesTableAnnotationComposer,
          $$GenerationPipelineStatusesTableCreateCompanionBuilder,
          $$GenerationPipelineStatusesTableUpdateCompanionBuilder,
          (
            GenerationPipelineStatusRow,
            BaseReferences<
              _$AppDatabase,
              $GenerationPipelineStatusesTable,
              GenerationPipelineStatusRow
            >,
          ),
          GenerationPipelineStatusRow,
          PrefetchHooks Function()
        > {
  $$GenerationPipelineStatusesTableTableManager(
    _$AppDatabase db,
    $GenerationPipelineStatusesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GenerationPipelineStatusesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$GenerationPipelineStatusesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$GenerationPipelineStatusesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> isBlocked = const Value.absent(),
                Value<String?> blockedReason = const Value.absent(),
                Value<String?> blockedAt = const Value.absent(),
                Value<int?> blockedAppVersionCode = const Value.absent(),
              }) => GenerationPipelineStatusesCompanion(
                id: id,
                isBlocked: isBlocked,
                blockedReason: blockedReason,
                blockedAt: blockedAt,
                blockedAppVersionCode: blockedAppVersionCode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required bool isBlocked,
                Value<String?> blockedReason = const Value.absent(),
                Value<String?> blockedAt = const Value.absent(),
                Value<int?> blockedAppVersionCode = const Value.absent(),
              }) => GenerationPipelineStatusesCompanion.insert(
                id: id,
                isBlocked: isBlocked,
                blockedReason: blockedReason,
                blockedAt: blockedAt,
                blockedAppVersionCode: blockedAppVersionCode,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GenerationPipelineStatusesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GenerationPipelineStatusesTable,
      GenerationPipelineStatusRow,
      $$GenerationPipelineStatusesTableFilterComposer,
      $$GenerationPipelineStatusesTableOrderingComposer,
      $$GenerationPipelineStatusesTableAnnotationComposer,
      $$GenerationPipelineStatusesTableCreateCompanionBuilder,
      $$GenerationPipelineStatusesTableUpdateCompanionBuilder,
      (
        GenerationPipelineStatusRow,
        BaseReferences<
          _$AppDatabase,
          $GenerationPipelineStatusesTable,
          GenerationPipelineStatusRow
        >,
      ),
      GenerationPipelineStatusRow,
      PrefetchHooks Function()
    >;
typedef $$DailyLearningLogsTableCreateCompanionBuilder =
    DailyLearningLogsCompanion Function({
      Value<int> id,
      required String logDate,
      required int articlesRead,
      required int wordsAdded,
      required int secondsSpent,
    });
typedef $$DailyLearningLogsTableUpdateCompanionBuilder =
    DailyLearningLogsCompanion Function({
      Value<int> id,
      Value<String> logDate,
      Value<int> articlesRead,
      Value<int> wordsAdded,
      Value<int> secondsSpent,
    });

class $$DailyLearningLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLearningLogsTable> {
  $$DailyLearningLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get logDate => $composableBuilder(
    column: $table.logDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get articlesRead => $composableBuilder(
    column: $table.articlesRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordsAdded => $composableBuilder(
    column: $table.wordsAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get secondsSpent => $composableBuilder(
    column: $table.secondsSpent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyLearningLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLearningLogsTable> {
  $$DailyLearningLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get logDate => $composableBuilder(
    column: $table.logDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get articlesRead => $composableBuilder(
    column: $table.articlesRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordsAdded => $composableBuilder(
    column: $table.wordsAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get secondsSpent => $composableBuilder(
    column: $table.secondsSpent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyLearningLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLearningLogsTable> {
  $$DailyLearningLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get logDate =>
      $composableBuilder(column: $table.logDate, builder: (column) => column);

  GeneratedColumn<int> get articlesRead => $composableBuilder(
    column: $table.articlesRead,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wordsAdded => $composableBuilder(
    column: $table.wordsAdded,
    builder: (column) => column,
  );

  GeneratedColumn<int> get secondsSpent => $composableBuilder(
    column: $table.secondsSpent,
    builder: (column) => column,
  );
}

class $$DailyLearningLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLearningLogsTable,
          DailyLearningLogRow,
          $$DailyLearningLogsTableFilterComposer,
          $$DailyLearningLogsTableOrderingComposer,
          $$DailyLearningLogsTableAnnotationComposer,
          $$DailyLearningLogsTableCreateCompanionBuilder,
          $$DailyLearningLogsTableUpdateCompanionBuilder,
          (
            DailyLearningLogRow,
            BaseReferences<
              _$AppDatabase,
              $DailyLearningLogsTable,
              DailyLearningLogRow
            >,
          ),
          DailyLearningLogRow,
          PrefetchHooks Function()
        > {
  $$DailyLearningLogsTableTableManager(
    _$AppDatabase db,
    $DailyLearningLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLearningLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLearningLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyLearningLogsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> logDate = const Value.absent(),
                Value<int> articlesRead = const Value.absent(),
                Value<int> wordsAdded = const Value.absent(),
                Value<int> secondsSpent = const Value.absent(),
              }) => DailyLearningLogsCompanion(
                id: id,
                logDate: logDate,
                articlesRead: articlesRead,
                wordsAdded: wordsAdded,
                secondsSpent: secondsSpent,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String logDate,
                required int articlesRead,
                required int wordsAdded,
                required int secondsSpent,
              }) => DailyLearningLogsCompanion.insert(
                id: id,
                logDate: logDate,
                articlesRead: articlesRead,
                wordsAdded: wordsAdded,
                secondsSpent: secondsSpent,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyLearningLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLearningLogsTable,
      DailyLearningLogRow,
      $$DailyLearningLogsTableFilterComposer,
      $$DailyLearningLogsTableOrderingComposer,
      $$DailyLearningLogsTableAnnotationComposer,
      $$DailyLearningLogsTableCreateCompanionBuilder,
      $$DailyLearningLogsTableUpdateCompanionBuilder,
      (
        DailyLearningLogRow,
        BaseReferences<
          _$AppDatabase,
          $DailyLearningLogsTable,
          DailyLearningLogRow
        >,
      ),
      DailyLearningLogRow,
      PrefetchHooks Function()
    >;
typedef $$LearningStatsSummariesTableCreateCompanionBuilder =
    LearningStatsSummariesCompanion Function({
      Value<int> id,
      required int totalArticlesRead,
      required int totalWordsAdded,
      required int totalWordsMastered,
      required int totalLearningDays,
      required int currentStreak,
      required int longestStreak,
      Value<String?> lastActiveDate,
    });
typedef $$LearningStatsSummariesTableUpdateCompanionBuilder =
    LearningStatsSummariesCompanion Function({
      Value<int> id,
      Value<int> totalArticlesRead,
      Value<int> totalWordsAdded,
      Value<int> totalWordsMastered,
      Value<int> totalLearningDays,
      Value<int> currentStreak,
      Value<int> longestStreak,
      Value<String?> lastActiveDate,
    });

class $$LearningStatsSummariesTableFilterComposer
    extends Composer<_$AppDatabase, $LearningStatsSummariesTable> {
  $$LearningStatsSummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalArticlesRead => $composableBuilder(
    column: $table.totalArticlesRead,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalWordsAdded => $composableBuilder(
    column: $table.totalWordsAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalWordsMastered => $composableBuilder(
    column: $table.totalWordsMastered,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalLearningDays => $composableBuilder(
    column: $table.totalLearningDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get longestStreak => $composableBuilder(
    column: $table.longestStreak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastActiveDate => $composableBuilder(
    column: $table.lastActiveDate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LearningStatsSummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $LearningStatsSummariesTable> {
  $$LearningStatsSummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalArticlesRead => $composableBuilder(
    column: $table.totalArticlesRead,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalWordsAdded => $composableBuilder(
    column: $table.totalWordsAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalWordsMastered => $composableBuilder(
    column: $table.totalWordsMastered,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalLearningDays => $composableBuilder(
    column: $table.totalLearningDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get longestStreak => $composableBuilder(
    column: $table.longestStreak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastActiveDate => $composableBuilder(
    column: $table.lastActiveDate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LearningStatsSummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LearningStatsSummariesTable> {
  $$LearningStatsSummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get totalArticlesRead => $composableBuilder(
    column: $table.totalArticlesRead,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalWordsAdded => $composableBuilder(
    column: $table.totalWordsAdded,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalWordsMastered => $composableBuilder(
    column: $table.totalWordsMastered,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalLearningDays => $composableBuilder(
    column: $table.totalLearningDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => column,
  );

  GeneratedColumn<int> get longestStreak => $composableBuilder(
    column: $table.longestStreak,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastActiveDate => $composableBuilder(
    column: $table.lastActiveDate,
    builder: (column) => column,
  );
}

class $$LearningStatsSummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LearningStatsSummariesTable,
          LearningStatsSummaryRow,
          $$LearningStatsSummariesTableFilterComposer,
          $$LearningStatsSummariesTableOrderingComposer,
          $$LearningStatsSummariesTableAnnotationComposer,
          $$LearningStatsSummariesTableCreateCompanionBuilder,
          $$LearningStatsSummariesTableUpdateCompanionBuilder,
          (
            LearningStatsSummaryRow,
            BaseReferences<
              _$AppDatabase,
              $LearningStatsSummariesTable,
              LearningStatsSummaryRow
            >,
          ),
          LearningStatsSummaryRow,
          PrefetchHooks Function()
        > {
  $$LearningStatsSummariesTableTableManager(
    _$AppDatabase db,
    $LearningStatsSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LearningStatsSummariesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LearningStatsSummariesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LearningStatsSummariesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> totalArticlesRead = const Value.absent(),
                Value<int> totalWordsAdded = const Value.absent(),
                Value<int> totalWordsMastered = const Value.absent(),
                Value<int> totalLearningDays = const Value.absent(),
                Value<int> currentStreak = const Value.absent(),
                Value<int> longestStreak = const Value.absent(),
                Value<String?> lastActiveDate = const Value.absent(),
              }) => LearningStatsSummariesCompanion(
                id: id,
                totalArticlesRead: totalArticlesRead,
                totalWordsAdded: totalWordsAdded,
                totalWordsMastered: totalWordsMastered,
                totalLearningDays: totalLearningDays,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                lastActiveDate: lastActiveDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int totalArticlesRead,
                required int totalWordsAdded,
                required int totalWordsMastered,
                required int totalLearningDays,
                required int currentStreak,
                required int longestStreak,
                Value<String?> lastActiveDate = const Value.absent(),
              }) => LearningStatsSummariesCompanion.insert(
                id: id,
                totalArticlesRead: totalArticlesRead,
                totalWordsAdded: totalWordsAdded,
                totalWordsMastered: totalWordsMastered,
                totalLearningDays: totalLearningDays,
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                lastActiveDate: lastActiveDate,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LearningStatsSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LearningStatsSummariesTable,
      LearningStatsSummaryRow,
      $$LearningStatsSummariesTableFilterComposer,
      $$LearningStatsSummariesTableOrderingComposer,
      $$LearningStatsSummariesTableAnnotationComposer,
      $$LearningStatsSummariesTableCreateCompanionBuilder,
      $$LearningStatsSummariesTableUpdateCompanionBuilder,
      (
        LearningStatsSummaryRow,
        BaseReferences<
          _$AppDatabase,
          $LearningStatsSummariesTable,
          LearningStatsSummaryRow
        >,
      ),
      LearningStatsSummaryRow,
      PrefetchHooks Function()
    >;
typedef $$ArticleBatchesTableCreateCompanionBuilder =
    ArticleBatchesCompanion Function({
      Value<int> id,
      required String status,
      required String difficultyLevelSnapshot,
      required String generatedOn,
      required String lastUpdatedAt,
      Value<String?> blockedReason,
      Value<String?> blockedAt,
      Value<int?> readyNotifiedAt,
    });
typedef $$ArticleBatchesTableUpdateCompanionBuilder =
    ArticleBatchesCompanion Function({
      Value<int> id,
      Value<String> status,
      Value<String> difficultyLevelSnapshot,
      Value<String> generatedOn,
      Value<String> lastUpdatedAt,
      Value<String?> blockedReason,
      Value<String?> blockedAt,
      Value<int?> readyNotifiedAt,
    });

final class $$ArticleBatchesTableReferences
    extends
        BaseReferences<_$AppDatabase, $ArticleBatchesTable, ArticleBatchRow> {
  $$ArticleBatchesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$DailyLearningsTable, List<DailyLearningRow>>
  _dailyLearningsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.dailyLearnings,
    aliasName: 'article_batch__id__daily_learning__ref_batch_id',
  );

  $$DailyLearningsTableProcessedTableManager get dailyLearningsRefs {
    final manager = $$DailyLearningsTableTableManager(
      $_db,
      $_db.dailyLearnings,
    ).filter((f) => f.refBatchId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_dailyLearningsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ArticlesTable, List<ArticleRow>>
  _articlesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.articles,
    aliasName: 'article_batch__id__article__batch_id',
  );

  $$ArticlesTableProcessedTableManager get articlesRefs {
    final manager = $$ArticlesTableTableManager(
      $_db,
      $_db.articles,
    ).filter((f) => f.batchId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_articlesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ArticleBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticleBatchesTable> {
  $$ArticleBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get difficultyLevelSnapshot => $composableBuilder(
    column: $table.difficultyLevelSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generatedOn => $composableBuilder(
    column: $table.generatedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastUpdatedAt => $composableBuilder(
    column: $table.lastUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readyNotifiedAt => $composableBuilder(
    column: $table.readyNotifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dailyLearningsRefs(
    Expression<bool> Function($$DailyLearningsTableFilterComposer f) f,
  ) {
    final $$DailyLearningsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyLearnings,
      getReferencedColumn: (t) => t.refBatchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyLearningsTableFilterComposer(
            $db: $db,
            $table: $db.dailyLearnings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> articlesRefs(
    Expression<bool> Function($$ArticlesTableFilterComposer f) f,
  ) {
    final $$ArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableFilterComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArticleBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticleBatchesTable> {
  $$ArticleBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get difficultyLevelSnapshot => $composableBuilder(
    column: $table.difficultyLevelSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generatedOn => $composableBuilder(
    column: $table.generatedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastUpdatedAt => $composableBuilder(
    column: $table.lastUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedAt => $composableBuilder(
    column: $table.blockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readyNotifiedAt => $composableBuilder(
    column: $table.readyNotifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ArticleBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticleBatchesTable> {
  $$ArticleBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get difficultyLevelSnapshot => $composableBuilder(
    column: $table.difficultyLevelSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get generatedOn => $composableBuilder(
    column: $table.generatedOn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastUpdatedAt => $composableBuilder(
    column: $table.lastUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get blockedAt =>
      $composableBuilder(column: $table.blockedAt, builder: (column) => column);

  GeneratedColumn<int> get readyNotifiedAt => $composableBuilder(
    column: $table.readyNotifiedAt,
    builder: (column) => column,
  );

  Expression<T> dailyLearningsRefs<T extends Object>(
    Expression<T> Function($$DailyLearningsTableAnnotationComposer a) f,
  ) {
    final $$DailyLearningsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.dailyLearnings,
      getReferencedColumn: (t) => t.refBatchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DailyLearningsTableAnnotationComposer(
            $db: $db,
            $table: $db.dailyLearnings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> articlesRefs<T extends Object>(
    Expression<T> Function($$ArticlesTableAnnotationComposer a) f,
  ) {
    final $$ArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.batchId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArticleBatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticleBatchesTable,
          ArticleBatchRow,
          $$ArticleBatchesTableFilterComposer,
          $$ArticleBatchesTableOrderingComposer,
          $$ArticleBatchesTableAnnotationComposer,
          $$ArticleBatchesTableCreateCompanionBuilder,
          $$ArticleBatchesTableUpdateCompanionBuilder,
          (ArticleBatchRow, $$ArticleBatchesTableReferences),
          ArticleBatchRow,
          PrefetchHooks Function({bool dailyLearningsRefs, bool articlesRefs})
        > {
  $$ArticleBatchesTableTableManager(
    _$AppDatabase db,
    $ArticleBatchesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticleBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticleBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticleBatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> difficultyLevelSnapshot = const Value.absent(),
                Value<String> generatedOn = const Value.absent(),
                Value<String> lastUpdatedAt = const Value.absent(),
                Value<String?> blockedReason = const Value.absent(),
                Value<String?> blockedAt = const Value.absent(),
                Value<int?> readyNotifiedAt = const Value.absent(),
              }) => ArticleBatchesCompanion(
                id: id,
                status: status,
                difficultyLevelSnapshot: difficultyLevelSnapshot,
                generatedOn: generatedOn,
                lastUpdatedAt: lastUpdatedAt,
                blockedReason: blockedReason,
                blockedAt: blockedAt,
                readyNotifiedAt: readyNotifiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String status,
                required String difficultyLevelSnapshot,
                required String generatedOn,
                required String lastUpdatedAt,
                Value<String?> blockedReason = const Value.absent(),
                Value<String?> blockedAt = const Value.absent(),
                Value<int?> readyNotifiedAt = const Value.absent(),
              }) => ArticleBatchesCompanion.insert(
                id: id,
                status: status,
                difficultyLevelSnapshot: difficultyLevelSnapshot,
                generatedOn: generatedOn,
                lastUpdatedAt: lastUpdatedAt,
                blockedReason: blockedReason,
                blockedAt: blockedAt,
                readyNotifiedAt: readyNotifiedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ArticleBatchesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({dailyLearningsRefs = false, articlesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dailyLearningsRefs) db.dailyLearnings,
                    if (articlesRefs) db.articles,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dailyLearningsRefs)
                        await $_getPrefetchedData<
                          ArticleBatchRow,
                          $ArticleBatchesTable,
                          DailyLearningRow
                        >(
                          currentTable: table,
                          referencedTable: $$ArticleBatchesTableReferences
                              ._dailyLearningsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ArticleBatchesTableReferences(
                                db,
                                table,
                                p0,
                              ).dailyLearningsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.refBatchId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (articlesRefs)
                        await $_getPrefetchedData<
                          ArticleBatchRow,
                          $ArticleBatchesTable,
                          ArticleRow
                        >(
                          currentTable: table,
                          referencedTable: $$ArticleBatchesTableReferences
                              ._articlesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ArticleBatchesTableReferences(
                                db,
                                table,
                                p0,
                              ).articlesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.batchId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ArticleBatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticleBatchesTable,
      ArticleBatchRow,
      $$ArticleBatchesTableFilterComposer,
      $$ArticleBatchesTableOrderingComposer,
      $$ArticleBatchesTableAnnotationComposer,
      $$ArticleBatchesTableCreateCompanionBuilder,
      $$ArticleBatchesTableUpdateCompanionBuilder,
      (ArticleBatchRow, $$ArticleBatchesTableReferences),
      ArticleBatchRow,
      PrefetchHooks Function({bool dailyLearningsRefs, bool articlesRefs})
    >;
typedef $$DailyLearningsTableCreateCompanionBuilder =
    DailyLearningsCompanion Function({
      required String learningDate,
      required String refBatchDate,
      required int refBatchId,
      required int dailyCountSnapshot,
      Value<int> rowid,
    });
typedef $$DailyLearningsTableUpdateCompanionBuilder =
    DailyLearningsCompanion Function({
      Value<String> learningDate,
      Value<String> refBatchDate,
      Value<int> refBatchId,
      Value<int> dailyCountSnapshot,
      Value<int> rowid,
    });

final class $$DailyLearningsTableReferences
    extends
        BaseReferences<_$AppDatabase, $DailyLearningsTable, DailyLearningRow> {
  $$DailyLearningsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ArticleBatchesTable _refBatchIdTable(_$AppDatabase db) => db
      .articleBatches
      .createAlias('daily_learning__ref_batch_id__article_batch__id');

  $$ArticleBatchesTableProcessedTableManager get refBatchId {
    final $_column = $_itemColumn<int>('ref_batch_id')!;

    final manager = $$ArticleBatchesTableTableManager(
      $_db,
      $_db.articleBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_refBatchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DailyLearningsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLearningsTable> {
  $$DailyLearningsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get learningDate => $composableBuilder(
    column: $table.learningDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refBatchDate => $composableBuilder(
    column: $table.refBatchDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyCountSnapshot => $composableBuilder(
    column: $table.dailyCountSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$ArticleBatchesTableFilterComposer get refBatchId {
    final $$ArticleBatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.refBatchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableFilterComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyLearningsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLearningsTable> {
  $$DailyLearningsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get learningDate => $composableBuilder(
    column: $table.learningDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refBatchDate => $composableBuilder(
    column: $table.refBatchDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyCountSnapshot => $composableBuilder(
    column: $table.dailyCountSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$ArticleBatchesTableOrderingComposer get refBatchId {
    final $$ArticleBatchesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.refBatchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableOrderingComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyLearningsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLearningsTable> {
  $$DailyLearningsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get learningDate => $composableBuilder(
    column: $table.learningDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refBatchDate => $composableBuilder(
    column: $table.refBatchDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dailyCountSnapshot => $composableBuilder(
    column: $table.dailyCountSnapshot,
    builder: (column) => column,
  );

  $$ArticleBatchesTableAnnotationComposer get refBatchId {
    final $$ArticleBatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.refBatchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DailyLearningsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLearningsTable,
          DailyLearningRow,
          $$DailyLearningsTableFilterComposer,
          $$DailyLearningsTableOrderingComposer,
          $$DailyLearningsTableAnnotationComposer,
          $$DailyLearningsTableCreateCompanionBuilder,
          $$DailyLearningsTableUpdateCompanionBuilder,
          (DailyLearningRow, $$DailyLearningsTableReferences),
          DailyLearningRow,
          PrefetchHooks Function({bool refBatchId})
        > {
  $$DailyLearningsTableTableManager(
    _$AppDatabase db,
    $DailyLearningsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLearningsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLearningsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyLearningsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> learningDate = const Value.absent(),
                Value<String> refBatchDate = const Value.absent(),
                Value<int> refBatchId = const Value.absent(),
                Value<int> dailyCountSnapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLearningsCompanion(
                learningDate: learningDate,
                refBatchDate: refBatchDate,
                refBatchId: refBatchId,
                dailyCountSnapshot: dailyCountSnapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String learningDate,
                required String refBatchDate,
                required int refBatchId,
                required int dailyCountSnapshot,
                Value<int> rowid = const Value.absent(),
              }) => DailyLearningsCompanion.insert(
                learningDate: learningDate,
                refBatchDate: refBatchDate,
                refBatchId: refBatchId,
                dailyCountSnapshot: dailyCountSnapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DailyLearningsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({refBatchId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (refBatchId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.refBatchId,
                                referencedTable: $$DailyLearningsTableReferences
                                    ._refBatchIdTable(db),
                                referencedColumn:
                                    $$DailyLearningsTableReferences
                                        ._refBatchIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DailyLearningsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLearningsTable,
      DailyLearningRow,
      $$DailyLearningsTableFilterComposer,
      $$DailyLearningsTableOrderingComposer,
      $$DailyLearningsTableAnnotationComposer,
      $$DailyLearningsTableCreateCompanionBuilder,
      $$DailyLearningsTableUpdateCompanionBuilder,
      (DailyLearningRow, $$DailyLearningsTableReferences),
      DailyLearningRow,
      PrefetchHooks Function({bool refBatchId})
    >;
typedef $$ArticlesTableCreateCompanionBuilder =
    ArticlesCompanion Function({
      Value<int> id,
      required int batchId,
      required int orderIndex,
      required String contentCategory,
      Value<String?> title,
      required String status,
      Value<String?> generationStartedAt,
      Value<String?> generationCompletedAt,
      required int retryCount,
      required int accumulatedReadSeconds,
      Value<String?> readCompletedAt,
      Value<String?> lastRetryAt,
      required int maxRetries,
      Value<String?> nextRetryAt,
    });
typedef $$ArticlesTableUpdateCompanionBuilder =
    ArticlesCompanion Function({
      Value<int> id,
      Value<int> batchId,
      Value<int> orderIndex,
      Value<String> contentCategory,
      Value<String?> title,
      Value<String> status,
      Value<String?> generationStartedAt,
      Value<String?> generationCompletedAt,
      Value<int> retryCount,
      Value<int> accumulatedReadSeconds,
      Value<String?> readCompletedAt,
      Value<String?> lastRetryAt,
      Value<int> maxRetries,
      Value<String?> nextRetryAt,
    });

final class $$ArticlesTableReferences
    extends BaseReferences<_$AppDatabase, $ArticlesTable, ArticleRow> {
  $$ArticlesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ArticleBatchesTable _batchIdTable(_$AppDatabase db) =>
      db.articleBatches.createAlias('article__batch_id__article_batch__id');

  $$ArticleBatchesTableProcessedTableManager get batchId {
    final $_column = $_itemColumn<int>('batch_id')!;

    final manager = $$ArticleBatchesTableTableManager(
      $_db,
      $_db.articleBatches,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_batchIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ArticleParagraphsTable, List<ArticleParagraphRow>>
  _articleParagraphsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.articleParagraphs,
        aliasName: 'article__id__article_paragraph__article_id',
      );

  $$ArticleParagraphsTableProcessedTableManager get articleParagraphsRefs {
    final manager = $$ArticleParagraphsTableTableManager(
      $_db,
      $_db.articleParagraphs,
    ).filter((f) => f.articleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _articleParagraphsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ArticlesTableFilterComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentCategory => $composableBuilder(
    column: $table.contentCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generationStartedAt => $composableBuilder(
    column: $table.generationStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get generationCompletedAt => $composableBuilder(
    column: $table.generationCompletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accumulatedReadSeconds => $composableBuilder(
    column: $table.accumulatedReadSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readCompletedAt => $composableBuilder(
    column: $table.readCompletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ArticleBatchesTableFilterComposer get batchId {
    final $$ArticleBatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableFilterComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> articleParagraphsRefs(
    Expression<bool> Function($$ArticleParagraphsTableFilterComposer f) f,
  ) {
    final $$ArticleParagraphsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.articleParagraphs,
      getReferencedColumn: (t) => t.articleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleParagraphsTableFilterComposer(
            $db: $db,
            $table: $db.articleParagraphs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ArticlesTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentCategory => $composableBuilder(
    column: $table.contentCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generationStartedAt => $composableBuilder(
    column: $table.generationStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get generationCompletedAt => $composableBuilder(
    column: $table.generationCompletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accumulatedReadSeconds => $composableBuilder(
    column: $table.accumulatedReadSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readCompletedAt => $composableBuilder(
    column: $table.readCompletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ArticleBatchesTableOrderingComposer get batchId {
    final $$ArticleBatchesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableOrderingComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ArticlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticlesTable> {
  $$ArticlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentCategory => $composableBuilder(
    column: $table.contentCategory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get generationStartedAt => $composableBuilder(
    column: $table.generationStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get generationCompletedAt => $composableBuilder(
    column: $table.generationCompletedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accumulatedReadSeconds => $composableBuilder(
    column: $table.accumulatedReadSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readCompletedAt => $composableBuilder(
    column: $table.readCompletedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastRetryAt => $composableBuilder(
    column: $table.lastRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxRetries => $composableBuilder(
    column: $table.maxRetries,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  $$ArticleBatchesTableAnnotationComposer get batchId {
    final $$ArticleBatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.batchId,
      referencedTable: $db.articleBatches,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticleBatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.articleBatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> articleParagraphsRefs<T extends Object>(
    Expression<T> Function($$ArticleParagraphsTableAnnotationComposer a) f,
  ) {
    final $$ArticleParagraphsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.articleParagraphs,
          getReferencedColumn: (t) => t.articleId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ArticleParagraphsTableAnnotationComposer(
                $db: $db,
                $table: $db.articleParagraphs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ArticlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticlesTable,
          ArticleRow,
          $$ArticlesTableFilterComposer,
          $$ArticlesTableOrderingComposer,
          $$ArticlesTableAnnotationComposer,
          $$ArticlesTableCreateCompanionBuilder,
          $$ArticlesTableUpdateCompanionBuilder,
          (ArticleRow, $$ArticlesTableReferences),
          ArticleRow,
          PrefetchHooks Function({bool batchId, bool articleParagraphsRefs})
        > {
  $$ArticlesTableTableManager(_$AppDatabase db, $ArticlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> batchId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<String> contentCategory = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> generationStartedAt = const Value.absent(),
                Value<String?> generationCompletedAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int> accumulatedReadSeconds = const Value.absent(),
                Value<String?> readCompletedAt = const Value.absent(),
                Value<String?> lastRetryAt = const Value.absent(),
                Value<int> maxRetries = const Value.absent(),
                Value<String?> nextRetryAt = const Value.absent(),
              }) => ArticlesCompanion(
                id: id,
                batchId: batchId,
                orderIndex: orderIndex,
                contentCategory: contentCategory,
                title: title,
                status: status,
                generationStartedAt: generationStartedAt,
                generationCompletedAt: generationCompletedAt,
                retryCount: retryCount,
                accumulatedReadSeconds: accumulatedReadSeconds,
                readCompletedAt: readCompletedAt,
                lastRetryAt: lastRetryAt,
                maxRetries: maxRetries,
                nextRetryAt: nextRetryAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int batchId,
                required int orderIndex,
                required String contentCategory,
                Value<String?> title = const Value.absent(),
                required String status,
                Value<String?> generationStartedAt = const Value.absent(),
                Value<String?> generationCompletedAt = const Value.absent(),
                required int retryCount,
                required int accumulatedReadSeconds,
                Value<String?> readCompletedAt = const Value.absent(),
                Value<String?> lastRetryAt = const Value.absent(),
                required int maxRetries,
                Value<String?> nextRetryAt = const Value.absent(),
              }) => ArticlesCompanion.insert(
                id: id,
                batchId: batchId,
                orderIndex: orderIndex,
                contentCategory: contentCategory,
                title: title,
                status: status,
                generationStartedAt: generationStartedAt,
                generationCompletedAt: generationCompletedAt,
                retryCount: retryCount,
                accumulatedReadSeconds: accumulatedReadSeconds,
                readCompletedAt: readCompletedAt,
                lastRetryAt: lastRetryAt,
                maxRetries: maxRetries,
                nextRetryAt: nextRetryAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ArticlesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({batchId = false, articleParagraphsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (articleParagraphsRefs) db.articleParagraphs,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (batchId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.batchId,
                                    referencedTable: $$ArticlesTableReferences
                                        ._batchIdTable(db),
                                    referencedColumn: $$ArticlesTableReferences
                                        ._batchIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (articleParagraphsRefs)
                        await $_getPrefetchedData<
                          ArticleRow,
                          $ArticlesTable,
                          ArticleParagraphRow
                        >(
                          currentTable: table,
                          referencedTable: $$ArticlesTableReferences
                              ._articleParagraphsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ArticlesTableReferences(
                                db,
                                table,
                                p0,
                              ).articleParagraphsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.articleId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ArticlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticlesTable,
      ArticleRow,
      $$ArticlesTableFilterComposer,
      $$ArticlesTableOrderingComposer,
      $$ArticlesTableAnnotationComposer,
      $$ArticlesTableCreateCompanionBuilder,
      $$ArticlesTableUpdateCompanionBuilder,
      (ArticleRow, $$ArticlesTableReferences),
      ArticleRow,
      PrefetchHooks Function({bool batchId, bool articleParagraphsRefs})
    >;
typedef $$ArticleParagraphsTableCreateCompanionBuilder =
    ArticleParagraphsCompanion Function({
      Value<int> id,
      required int articleId,
      required int orderIndex,
      required String englishText,
      required String chineseTranslation,
    });
typedef $$ArticleParagraphsTableUpdateCompanionBuilder =
    ArticleParagraphsCompanion Function({
      Value<int> id,
      Value<int> articleId,
      Value<int> orderIndex,
      Value<String> englishText,
      Value<String> chineseTranslation,
    });

final class $$ArticleParagraphsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ArticleParagraphsTable,
          ArticleParagraphRow
        > {
  $$ArticleParagraphsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ArticlesTable _articleIdTable(_$AppDatabase db) =>
      db.articles.createAlias('article_paragraph__article_id__article__id');

  $$ArticlesTableProcessedTableManager get articleId {
    final $_column = $_itemColumn<int>('article_id')!;

    final manager = $$ArticlesTableTableManager(
      $_db,
      $_db.articles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_articleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ArticleParagraphsTableFilterComposer
    extends Composer<_$AppDatabase, $ArticleParagraphsTable> {
  $$ArticleParagraphsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get englishText => $composableBuilder(
    column: $table.englishText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chineseTranslation => $composableBuilder(
    column: $table.chineseTranslation,
    builder: (column) => ColumnFilters(column),
  );

  $$ArticlesTableFilterComposer get articleId {
    final $$ArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableFilterComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ArticleParagraphsTableOrderingComposer
    extends Composer<_$AppDatabase, $ArticleParagraphsTable> {
  $$ArticleParagraphsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get englishText => $composableBuilder(
    column: $table.englishText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chineseTranslation => $composableBuilder(
    column: $table.chineseTranslation,
    builder: (column) => ColumnOrderings(column),
  );

  $$ArticlesTableOrderingComposer get articleId {
    final $$ArticlesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableOrderingComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ArticleParagraphsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ArticleParagraphsTable> {
  $$ArticleParagraphsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
    column: $table.orderIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get englishText => $composableBuilder(
    column: $table.englishText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chineseTranslation => $composableBuilder(
    column: $table.chineseTranslation,
    builder: (column) => column,
  );

  $$ArticlesTableAnnotationComposer get articleId {
    final $$ArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.articleId,
      referencedTable: $db.articles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.articles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ArticleParagraphsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ArticleParagraphsTable,
          ArticleParagraphRow,
          $$ArticleParagraphsTableFilterComposer,
          $$ArticleParagraphsTableOrderingComposer,
          $$ArticleParagraphsTableAnnotationComposer,
          $$ArticleParagraphsTableCreateCompanionBuilder,
          $$ArticleParagraphsTableUpdateCompanionBuilder,
          (ArticleParagraphRow, $$ArticleParagraphsTableReferences),
          ArticleParagraphRow,
          PrefetchHooks Function({bool articleId})
        > {
  $$ArticleParagraphsTableTableManager(
    _$AppDatabase db,
    $ArticleParagraphsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ArticleParagraphsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ArticleParagraphsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ArticleParagraphsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> articleId = const Value.absent(),
                Value<int> orderIndex = const Value.absent(),
                Value<String> englishText = const Value.absent(),
                Value<String> chineseTranslation = const Value.absent(),
              }) => ArticleParagraphsCompanion(
                id: id,
                articleId: articleId,
                orderIndex: orderIndex,
                englishText: englishText,
                chineseTranslation: chineseTranslation,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int articleId,
                required int orderIndex,
                required String englishText,
                required String chineseTranslation,
              }) => ArticleParagraphsCompanion.insert(
                id: id,
                articleId: articleId,
                orderIndex: orderIndex,
                englishText: englishText,
                chineseTranslation: chineseTranslation,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ArticleParagraphsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({articleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (articleId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.articleId,
                                referencedTable:
                                    $$ArticleParagraphsTableReferences
                                        ._articleIdTable(db),
                                referencedColumn:
                                    $$ArticleParagraphsTableReferences
                                        ._articleIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ArticleParagraphsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ArticleParagraphsTable,
      ArticleParagraphRow,
      $$ArticleParagraphsTableFilterComposer,
      $$ArticleParagraphsTableOrderingComposer,
      $$ArticleParagraphsTableAnnotationComposer,
      $$ArticleParagraphsTableCreateCompanionBuilder,
      $$ArticleParagraphsTableUpdateCompanionBuilder,
      (ArticleParagraphRow, $$ArticleParagraphsTableReferences),
      ArticleParagraphRow,
      PrefetchHooks Function({bool articleId})
    >;
typedef $$GenerationErrorLogsTableCreateCompanionBuilder =
    GenerationErrorLogsCompanion Function({
      Value<int> id,
      required String entityType,
      required int entityId,
      required String errorCode,
      required String errorMessage,
      Value<String?> errorHelp,
      required int retryCount,
      required String createdAt,
      Value<int?> notifiedAt,
    });
typedef $$GenerationErrorLogsTableUpdateCompanionBuilder =
    GenerationErrorLogsCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<int> entityId,
      Value<String> errorCode,
      Value<String> errorMessage,
      Value<String?> errorHelp,
      Value<int> retryCount,
      Value<String> createdAt,
      Value<int?> notifiedAt,
    });

class $$GenerationErrorLogsTableFilterComposer
    extends Composer<_$AppDatabase, $GenerationErrorLogsTable> {
  $$GenerationErrorLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorHelp => $composableBuilder(
    column: $table.errorHelp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notifiedAt => $composableBuilder(
    column: $table.notifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GenerationErrorLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $GenerationErrorLogsTable> {
  $$GenerationErrorLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorHelp => $composableBuilder(
    column: $table.errorHelp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notifiedAt => $composableBuilder(
    column: $table.notifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GenerationErrorLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GenerationErrorLogsTable> {
  $$GenerationErrorLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorHelp =>
      $composableBuilder(column: $table.errorHelp, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get notifiedAt => $composableBuilder(
    column: $table.notifiedAt,
    builder: (column) => column,
  );
}

class $$GenerationErrorLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GenerationErrorLogsTable,
          GenerationErrorLogRow,
          $$GenerationErrorLogsTableFilterComposer,
          $$GenerationErrorLogsTableOrderingComposer,
          $$GenerationErrorLogsTableAnnotationComposer,
          $$GenerationErrorLogsTableCreateCompanionBuilder,
          $$GenerationErrorLogsTableUpdateCompanionBuilder,
          (
            GenerationErrorLogRow,
            BaseReferences<
              _$AppDatabase,
              $GenerationErrorLogsTable,
              GenerationErrorLogRow
            >,
          ),
          GenerationErrorLogRow,
          PrefetchHooks Function()
        > {
  $$GenerationErrorLogsTableTableManager(
    _$AppDatabase db,
    $GenerationErrorLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GenerationErrorLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GenerationErrorLogsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$GenerationErrorLogsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<int> entityId = const Value.absent(),
                Value<String> errorCode = const Value.absent(),
                Value<String> errorMessage = const Value.absent(),
                Value<String?> errorHelp = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int?> notifiedAt = const Value.absent(),
              }) => GenerationErrorLogsCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                errorCode: errorCode,
                errorMessage: errorMessage,
                errorHelp: errorHelp,
                retryCount: retryCount,
                createdAt: createdAt,
                notifiedAt: notifiedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required int entityId,
                required String errorCode,
                required String errorMessage,
                Value<String?> errorHelp = const Value.absent(),
                required int retryCount,
                required String createdAt,
                Value<int?> notifiedAt = const Value.absent(),
              }) => GenerationErrorLogsCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                errorCode: errorCode,
                errorMessage: errorMessage,
                errorHelp: errorHelp,
                retryCount: retryCount,
                createdAt: createdAt,
                notifiedAt: notifiedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GenerationErrorLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GenerationErrorLogsTable,
      GenerationErrorLogRow,
      $$GenerationErrorLogsTableFilterComposer,
      $$GenerationErrorLogsTableOrderingComposer,
      $$GenerationErrorLogsTableAnnotationComposer,
      $$GenerationErrorLogsTableCreateCompanionBuilder,
      $$GenerationErrorLogsTableUpdateCompanionBuilder,
      (
        GenerationErrorLogRow,
        BaseReferences<
          _$AppDatabase,
          $GenerationErrorLogsTable,
          GenerationErrorLogRow
        >,
      ),
      GenerationErrorLogRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
  $$ConfigChangeLogsTableTableManager get configChangeLogs =>
      $$ConfigChangeLogsTableTableManager(_db, _db.configChangeLogs);
  $$SchemaMigrationLogsTableTableManager get schemaMigrationLogs =>
      $$SchemaMigrationLogsTableTableManager(_db, _db.schemaMigrationLogs);
  $$GenerationPipelineStatusesTableTableManager
  get generationPipelineStatuses =>
      $$GenerationPipelineStatusesTableTableManager(
        _db,
        _db.generationPipelineStatuses,
      );
  $$DailyLearningLogsTableTableManager get dailyLearningLogs =>
      $$DailyLearningLogsTableTableManager(_db, _db.dailyLearningLogs);
  $$LearningStatsSummariesTableTableManager get learningStatsSummaries =>
      $$LearningStatsSummariesTableTableManager(
        _db,
        _db.learningStatsSummaries,
      );
  $$ArticleBatchesTableTableManager get articleBatches =>
      $$ArticleBatchesTableTableManager(_db, _db.articleBatches);
  $$DailyLearningsTableTableManager get dailyLearnings =>
      $$DailyLearningsTableTableManager(_db, _db.dailyLearnings);
  $$ArticlesTableTableManager get articles =>
      $$ArticlesTableTableManager(_db, _db.articles);
  $$ArticleParagraphsTableTableManager get articleParagraphs =>
      $$ArticleParagraphsTableTableManager(_db, _db.articleParagraphs);
  $$GenerationErrorLogsTableTableManager get generationErrorLogs =>
      $$GenerationErrorLogsTableTableManager(_db, _db.generationErrorLogs);
}
