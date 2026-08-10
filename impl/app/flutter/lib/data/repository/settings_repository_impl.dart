import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../../domain/model/user_settings.dart';
import '../../domain/repository/settings_repository.dart';
import '../local/database.dart';
import '../local/daos/settings_daos.dart';

/// 设置仓储实现（对照 Kotlin SettingsRepositoryImpl.kt）。
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._settingsDao);

  final UserSettingsDao _settingsDao;

  @override
  Stream<UserSettings?> observeSettings() =>
      _settingsDao.observe().map((row) => row?.toModel());

  @override
  Future<UserSettings?> getSettings() async {
    final row = await _settingsDao.get();
    return row?.toModel();
  }

  @override
  Future<bool> isOnboarded() async =>
      (await _settingsDao.get())?.isOnboarded == true;

  @override
  Future<void> completeOnboarding(String level, int dailyCount) async {
    final existing = await _settingsDao.get();
    await _settingsDao.upsert((existing ?? const UserSettingsRow(
      id: 1,
      isOnboarded: false,
      difficultyLevel: 'MEDIUM',
      dailyArticleCount: 3,
      translationDisplayMode: 'FULL',
      ttsSpeed: 1.0,
      // Task 2 加列：默认音色 BELLA（TtsVoice.dbValue 字面量，Task 3 接入枚举）
      ttsVoiceId: 'BELLA',
      masteryThresholdN: 1,
      autoPlayAudio: false,
    )).toCompanion(true).copyWith(
      isOnboarded: const Value(true),
      difficultyLevel: Value(level),
      dailyArticleCount: Value(dailyCount),
    ));
  }

  @override
  Future<void> updateLevel(String level) async {
    final existing = await _settingsDao.get();
    if (existing == null) return;
    await _settingsDao.upsert(
        existing.toCompanion(true).copyWith(difficultyLevel: Value(level)));
  }

  @override
  Future<bool> updateDailyArticleCount(int newCount) async {
    final existing = await _settingsDao.get();
    if (existing == null) return false;
    if (newCount == existing.dailyArticleCount) return false;
    if (newCount < 1 || newCount > 5) return false;
    await _settingsDao.upsert(
        existing.toCompanion(true).copyWith(dailyArticleCount: Value(newCount)));
    return true;
  }

  @override
  Future<void> updateTranslationMode(String mode) async {
    final existing = await _settingsDao.get();
    if (existing == null) return;
    await _settingsDao.upsert(
        existing.toCompanion(true).copyWith(translationDisplayMode: Value(mode)));
  }

  @override
  Future<void> updateTtsSpeed(double speed) async {
    final existing = await _settingsDao.get();
    if (existing == null) return;
    await _settingsDao.upsert(
        existing.toCompanion(true).copyWith(ttsSpeed: Value(speed)));
  }

  @override
  Future<void> updateMasteryThreshold(int n) async {
    final existing = await _settingsDao.get();
    if (existing == null) return;
    final clamped = n < 1 ? 1 : (n > 5 ? 5 : n);
    await _settingsDao
        .upsert(existing.toCompanion(true).copyWith(masteryThresholdN: Value(clamped)));
  }

  @override
  Future<void> updateAutoPlayAudio(bool enabled) async {
    final existing = await _settingsDao.get();
    if (existing == null) return;
    await _settingsDao
        .upsert(existing.toCompanion(true).copyWith(autoPlayAudio: Value(enabled)));
  }
}

extension on UserSettingsRow {
  UserSettings toModel() => UserSettings(
        id: id,
        isOnboarded: isOnboarded,
        difficultyLevel: difficultyLevel,
        dailyArticleCount: dailyArticleCount,
        translationDisplayMode: translationDisplayMode,
        ttsSpeed: ttsSpeed,
        masteryThresholdN: masteryThresholdN,
        autoPlayAudio: autoPlayAudio,
      );
}
