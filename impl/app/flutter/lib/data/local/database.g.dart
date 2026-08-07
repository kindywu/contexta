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
  late final Index indexDailyLearningRefBatchId = Index(
    'index_daily_learning_ref_batch_id',
    'CREATE INDEX index_daily_learning_ref_batch_id ON daily_learning (ref_batch_id)',
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
    indexDailyLearningRefBatchId,
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
          PrefetchHooks Function({bool dailyLearningsRefs})
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
          prefetchHooksCallback: ({dailyLearningsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (dailyLearningsRefs) db.dailyLearnings,
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
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.refBatchId == item.id),
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
      PrefetchHooks Function({bool dailyLearningsRefs})
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
}
