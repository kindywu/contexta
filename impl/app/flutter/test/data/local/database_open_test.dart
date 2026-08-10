import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/data/local/database_open.dart';

/// Task 7 数据库打开策略测试。
///
/// - resolveDatabasePath 纯函数：Android 对齐 Room 默认路径
///   `/data/data/<pkg>/databases/contexta.db`（覆盖安装必须打开旧库）；
///   非 Android 用 Documents 目录下的 contexta.db
/// - buildAppDatabase 集成：overridePath 注入 + 全新库自动种种子 +
///   PRAGMA foreign_keys = ON + 二次打开不重复写
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveDatabasePath（纯函数）', () {
    test('Android：baseDir=<pkg>/files 时拼接 <pkg>/databases/contexta.db', () {
      // getApplicationSupportDirectory() 在 Android 返回 /data/data/<pkg>/files
      final path = resolveDatabasePath(
        baseDir: '/data/data/com.ak.contexta/files',
        isAndroid: true,
      );
      expect(path, '/data/data/com.ak.contexta/databases/contexta.db');
    });

    test('非 Android：Documents 目录下直接放 contexta.db', () {
      final path = resolveDatabasePath(
        baseDir: '/var/mobile/Containers/Data/Application/ABC/Documents',
        isAndroid: false,
      );
      expect(
        path,
        '/var/mobile/Containers/Data/Application/ABC/Documents/contexta.db',
      );
    });
  });

  group('buildAppDatabase', () {
    test('overridePath 打开全新库：FK 开启 + 种子写入', () async {
      final dir = await Directory.systemTemp.createTemp('contexta_open_test');
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = '${dir.path}/contexta.db';

      final db = await buildAppDatabase(overridePath: dbPath);
      addTearDown(db.close);

      // 种子已通过 MigrationStrategy.onCreate 写入
      final batches = await db.select(db.articleBatches).get();
      expect(batches.length, 3);
      expect(batches.map((b) => b.status).toSet(), {'READY'});
      expect((await db.select(db.articles).get()).length, 15);
      expect((await db.select(db.articleParagraphs).get()).length, 105);

      // beforeOpen 已执行 PRAGMA foreign_keys = ON（Room 默认开启，必须对齐）
      final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(fk.read<int>('foreign_keys'), 1);
    });

    test('二次打开同一文件不重复种种子', () async {
      final dir = await Directory.systemTemp.createTemp('contexta_open_test');
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = '${dir.path}/contexta.db';

      final db1 = await buildAppDatabase(overridePath: dbPath);
      expect((await db1.select(db1.articleBatches).get()).length, 3);
      await db1.close();

      final db2 = await buildAppDatabase(overridePath: dbPath);
      addTearDown(db2.close);
      expect((await db2.select(db2.articleBatches).get()).length, 3);
      expect((await db2.select(db2.articles).get()).length, 15);
      expect((await db2.select(db2.articleParagraphs).get()).length, 105);
    });
  });
}
