import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'seed/seed_database.dart';

/// 打开策略（Task 7）：
/// - 全新库：onCreate → createAll + 种子写入（等价 Room onCreate 回调）
/// - 每次打开：beforeOpen → PRAGMA foreign_keys = ON（Room 默认开启，必须对齐）
///
/// [overridePath] 注入能力保留给 Task 8（用备份库 fixture 验证路径语义）。
Future<AppDatabase> buildAppDatabase({String? overridePath}) async {
  final path = overridePath ?? await _dbPath();
  late final AppDatabase db;
  db = AppDatabase.open(
    NativeDatabase.createInBackground(File(path)),
    migrationStrategy: MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        // 全新库才走到这（等价 Room onCreate）；writeSeedIfNeeded 内部
        // 还有空表检查，防御任何重复写入路径
        await writeSeedIfNeeded(db);
      },
      beforeOpen: (details) async {
        await db.customStatement('PRAGMA foreign_keys = ON');
      },
    ),
  );
  return db;
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
