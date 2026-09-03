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

  group('beforeOpen 自愈（登录态 + 文章同步列）', () {
    /// 拷贝旧结构 fixture（test/fixtures/legacy/contexta.db）到临时目录。
    /// WAL 三件套齐拉（主文件 + -wal + -shm），保证打开即最新状态。
    Future<Directory> copyLegacyFixture() async {
      final tmp = await Directory.systemTemp.createTemp('contexta-heal-');
      File('test/fixtures/legacy/contexta.db').copySync('${tmp.path}/contexta.db');
      for (final suffix in ['-wal', '-shm']) {
        final src = File('test/fixtures/legacy/contexta.db$suffix');
        if (src.existsSync()) {
          src.copySync('${tmp.path}/contexta.db$suffix');
        }
      }
      return tmp;
    }

    test('打开旧结构库自愈：user_settings 补 3 登录态列、article 补 server_article_id + 唯一索引，已有数据不丢', () async {
      final tmp = await copyLegacyFixture();
      final db = await buildAppDatabase(overridePath: '${tmp.path}/contexta.db');
      addTearDown(() async {
        await db.close();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // user_settings：server_phone / server_token（TEXT nullable）+
      // server_token_expires_at（INTEGER nullable）
      final usCols = await db.customSelect(
        "SELECT name, type, \"notnull\" FROM pragma_table_info('user_settings')",
      ).get();
      final usByName = {for (final r in usCols) r.read<String>('name'): r};
      expect(usByName['server_phone']!.read<String>('type'), 'TEXT');
      expect(usByName['server_phone']!.read<int>('notnull'), 0);
      expect(usByName['server_token']!.read<String>('type'), 'TEXT');
      expect(usByName['server_token']!.read<int>('notnull'), 0);
      expect(usByName['server_token_expires_at']!.read<String>('type'), 'INTEGER');
      expect(usByName['server_token_expires_at']!.read<int>('notnull'), 0);

      // article：server_article_id（INTEGER nullable）+ 唯一索引
      // （SQLite UNIQUE 允许多 NULL —— 同步幂等键语义）
      final aCols = await db.customSelect(
        "SELECT name, type, \"notnull\" FROM pragma_table_info('article')",
      ).get();
      final aByName = {for (final r in aCols) r.read<String>('name'): r};
      expect(aByName['server_article_id']!.read<String>('type'), 'INTEGER');
      expect(aByName['server_article_id']!.read<int>('notnull'), 0);

      final idx = await db.customSelect(
        "SELECT name, \"unique\" FROM pragma_index_list('article') "
        "WHERE name = 'index_article_server_article_id'",
      ).get();
      expect(idx, hasLength(1), reason: '自愈应建出同步幂等键唯一索引');
      expect(idx.single.read<int>('unique'), 1);

      // 已有表数据不丢（fixture 基线：user_settings 单行、article 60 行）
      final usCount = await db
          .customSelect('SELECT count(*) AS c FROM user_settings')
          .getSingle();
      expect(usCount.read<int>('c'), 1);
      final artCount =
          await db.customSelect('SELECT count(*) AS c FROM article').getSingle();
      expect(artCount.read<int>('c'), 60);
    });

    test('二次打开幂等：不重复补列、不重复建索引', () async {
      final tmp = await copyLegacyFixture();
      final db1 = await buildAppDatabase(overridePath: '${tmp.path}/contexta.db');
      await db1.close();

      final db2 = await buildAppDatabase(overridePath: '${tmp.path}/contexta.db');
      addTearDown(() async {
        await db2.close();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final usCols = await db2.customSelect(
        "SELECT name FROM pragma_table_info('user_settings')",
      ).get();
      expect(
        usCols
            .map((r) => r.read<String>('name'))
            .where((n) => n.startsWith('server_'))
            .toList(),
        ['server_phone', 'server_token', 'server_token_expires_at'],
      );
      final idx = await db2.customSelect(
        "SELECT count(*) AS c FROM pragma_index_list('article') "
        "WHERE name = 'index_article_server_article_id'",
      ).getSingle();
      expect(idx.read<int>('c'), 1, reason: '索引幂等：二次打开不重复建');
    });
  });
}
