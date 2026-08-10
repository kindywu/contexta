import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../di/providers.dart';
import 'article_generation_worker_handler.dart';
import 'generation_scheduler.dart';

/// workmanager 回调派发器：后台 isolate 中由插件调用，构建最小依赖图
/// （数据库 + 仓储 + use case），执行批次生成。
///
/// 必须保持顶层函数 + `@pragma('vm:entry-point')`（后台 isolate 通过
/// entry point 发现它，不能被 tree-shake 掉）。
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  debugPrint('[WorkerDispatcher] backgroundCallbackDispatcher ENTER');
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[WorkerDispatcher] executeTask taskName=$taskName inputData=$inputData');
    if (taskName != GenerationScheduler.taskName) {
      stderr.writeln('backgroundCallbackDispatcher: unknown task: $taskName');
      return true;
    }
    // 后台 isolate 是全新 isolate，须重建 Riverpod 容器（与 UI isolate
    // 不共享状态；容器生命周期仅覆盖本次任务执行）。
    final container = ProviderContainer();
    try {
      await container.read(databaseProvider.future);
      final handler = ArticleGenerationWorkerHandler(
        articleRepository:
            container.read(articleRepositoryProvider),
        generateArticles:
            container.read(generateArticlesUseCaseProvider),
      );
      final result = await handler.run(inputData);
      debugPrint('[WorkerDispatcher] handler result=$result');
      return result;
    } catch (e) {
      debugPrint('[WorkerDispatcher] ERROR: $e');
      rethrow;
    } finally {
      // 关闭数据库连接，避免后台 isolate 泄漏句柄
      await container
          .read(databaseProvider.future)
          .then((db) => db.close(), onError: (_) {});
      container.dispose();
    }
  });
}
