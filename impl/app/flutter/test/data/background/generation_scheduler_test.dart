import 'package:contexta/data/background/generation_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

/// GenerationScheduler 测试（对照 Kotlin GenerationSchedulerTest 语义）：
/// - uniqueWorkName = `article_generation_batch_<id>` + KEEP 策略 + 指数退避 30s
/// - tag = `batch_<id>`；expedited + 前台通知（channel 文章生成/标题/正文/1001）
/// - cancelBatchGeneration → cancelByUniqueName；cancelAllGeneration →
///   cancelByTag("article_generation")
void main() {
  late _FakeGateway gateway;
  late GenerationScheduler scheduler;

  setUp(() {
    gateway = _FakeGateway();
    scheduler = GenerationScheduler.unittest(gateway);
  });

  group('scheduleBatchGeneration', () {
    test('注册一次性任务：uniqueName/taskName/inputData/tag/expedited', () async {
      final ok = await scheduler.scheduleBatchGeneration(6);

      expect(ok, isTrue);
      expect(gateway.registered, hasLength(1));
      final spec = gateway.registered.single;
      expect(spec.uniqueName, 'article_generation_batch_6');
      expect(spec.taskName, 'articleGeneration');
      expect(spec.inputData, {'batchId': 6, 'appVersionCode': 0});
      expect(spec.tag, 'batch_6');
      expect(spec.expedited, isTrue);
    });

    test('KEEP 策略 + 指数退避 30s（Kotlin ExistingWorkPolicy.KEEP / '
        'BackoffPolicy.EXPONENTIAL 30s）', () async {
      await scheduler.scheduleBatchGeneration(6);

      final spec = gateway.registered.single;
      expect(spec.existingWorkPolicy, ExistingWorkPolicy.keep);
      expect(spec.backoffPolicy, BackoffPolicy.exponential);
      expect(spec.backoffPolicyDelay, const Duration(seconds: 30));
      expect(spec.outOfQuotaPolicy, OutOfQuotaPolicy.runAsNonExpeditedWorkRequest);
    });

    test('前台服务通知：channel 文章生成 + 标题/正文/notificationId + '
        'shortService 类型', () async {
      await scheduler.scheduleBatchGeneration(6);

      final config = gateway.registered.single.foregroundServiceConfig;
      expect(config, isNotNull);
      expect(config!.notificationChannelId, 'article_generation');
      expect(config.notificationChannelName, '文章生成');
      expect(config.notificationTitle, 'Contexta 正在生成文章');
      expect(config.notificationText, '批次 #6 生成中…');
      expect(config.notificationId, 1001);
      expect(config.foregroundServiceType, ForegroundServiceType.shortService);
    });

    test('batchId 缺失/非法时通知正文用 "生成中…"（Kotlin getForegroundInfo '
        'batchId <= 0 分支）', () {
      final config = GenerationScheduler.foregroundConfig(-1);
      expect(config.notificationText, '生成中…');
    });

    test('appVersionCode 透传进 inputData', () async {
      await scheduler.scheduleBatchGeneration(6, appVersionCode: 12);

      final spec = gateway.registered.single;
      expect(spec.inputData, {'batchId': 6, 'appVersionCode': 12});
    });

    test('不同批次用不同 uniqueName（各自独立调度）', () async {
      await scheduler.scheduleBatchGeneration(6);
      await scheduler.scheduleBatchGeneration(7);

      expect(gateway.registered.map((s) => s.uniqueName),
          ['article_generation_batch_6', 'article_generation_batch_7']);
    });
  });

  group('cancel', () {
    test('cancelBatchGeneration → cancelByUniqueName(batch 前缀)', () async {
      await scheduler.cancelBatchGeneration(6);
      expect(gateway.cancelledByUniqueName, ['article_generation_batch_6']);
    });

    test('cancelAllGeneration → cancelByTag(article_generation)', () async {
      await scheduler.cancelAllGeneration();
      expect(gateway.cancelledByTag, ['article_generation']);
    });
  });
}

class _FakeGateway implements WorkmanagerGateway {
  final List<GenerationTaskSpec> registered = [];
  final List<String> cancelledByUniqueName = [];
  final List<String> cancelledByTag = [];
  bool cancelAllCalled = false;

  @override
  Future<void> registerOneOffTask(GenerationTaskSpec spec) async {
    registered.add(spec);
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelledByUniqueName.add(uniqueName);
  }

  @override
  Future<void> cancelByTag(String tag) async {
    cancelledByTag.add(tag);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
  }
}
