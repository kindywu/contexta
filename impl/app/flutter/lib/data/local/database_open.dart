import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'seed/seed_database.dart';

/// 打开策略（Task 7）：
/// - 全新安装（目标路径无 DB）：从 asset 复制预置库（`.backup/contexta-db-*`），
///   该库已含种子数据，跳过种子写入
/// - 已有 DB：直接打开（覆盖安装 / 数据升级）
/// - 每次打开：beforeOpen → PRAGMA foreign_keys = ON（Room 默认开启，必须对齐）
///
/// [overridePath] 注入能力保留给测试（用备份库 fixture 验证路径语义）。
Future<AppDatabase> buildAppDatabase({String? overridePath}) async {
  final path = overridePath ?? await _dbPath();
  late final AppDatabase db;

  // 全新安装：从 asset 复制预置数据库
  if (overridePath == null && !File(path).existsSync()) {
    await _copyBundledDatabase(path);
  }

  db = AppDatabase.open(
    NativeDatabase.createInBackground(File(path)),
    migrationStrategy: MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        // 只有当 asset 预置库未能部署时才会走到这里；正常路径下
        // 数据库已从 asset 复制，onCreate 不会触发。
        await writeSeedIfNeeded(db);
      },
      beforeOpen: (details) async {
        await db.customStatement('PRAGMA foreign_keys = ON');
      },
    ),
  );
  return db;
}

/// 从 asset 复制预置数据库到目标路径。
///
/// SQLite 的 [open] 行为：如果文件不存在则自动创建空库并触发 onCreate。
/// 所以必须 _先_ 写入再 [open]，否则不会走到 asset 复制路径。
///
/// 注意：此操作仅在数据库文件尚不存在时执行（见调用方的 [existsSync] 检查），
/// 所以覆盖安装 / 数据升级时不会覆盖已有数据。
Future<void> _copyBundledDatabase(String targetPath) async {
  try {
    final data = await rootBundle.load('assets/contexta.db');
    final dir = Directory(p.dirname(targetPath));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(targetPath);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  } catch (e) {
    // asset 缺失或 IO 错误时退回到种子写入路径：删除可能的不完整文件，
    // 下层的 open → onCreate → writeSeedIfNeeded 会兜底。
    try {
      File(targetPath).deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// 数据库文件路径的纯函数构造（可单测）。
///
/// Android 覆盖安装时必须打开 Room 旧库 `/data/data/<pkg>/databases/contexta.db`
/// （AppModule.kt 用 Room 默认 "contexta.db"）。drift_flutter 的
/// `driftDatabase(name:)` 默认用 `getApplicationDocumentsDirectory()`（Android
/// 为 `<pkg>/app_flutter/`），与 Room 路径不同，因此这里手工构造。
///
/// [baseDir] 约定：
/// - Android：getApplicationSupportDirectory() 的返回（= `<pkg>/files`），
///   取其 parent（`<pkg>`）再拼 `databases/contexta.db`
/// - 非 Android：getApplicationDocumentsDirectory() 的返回，直接放 `contexta.db`
String resolveDatabasePath({required String baseDir, required bool isAndroid}) {
  if (isAndroid) {
    final pkgDir = Directory(baseDir).parent.path;
    return '$pkgDir/databases/contexta.db';
  }
  return '$baseDir/contexta.db';
}

/// 平台相关的路径解析（依赖 path_provider，不进纯函数）。
Future<String> _dbPath() async {
  if (Platform.isAndroid) {
    final support = await getApplicationSupportDirectory();
    return resolveDatabasePath(baseDir: support.path, isAndroid: true);
  }
  final docs = await getApplicationDocumentsDirectory();
  return resolveDatabasePath(baseDir: docs.path, isAndroid: false);
}
