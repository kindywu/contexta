import 'package:contexta/domain/error/pipeline_blocking_exception.dart';
import 'package:contexta/domain/llm_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// 对照 Android LlmErrorClassifier.kt 的分类语义逐分支移植。
void main() {
  group('LlmErrorClassifier', () {
    test('PipelineBlockingException 实例 → Structural', () {
      final result = LlmErrorClassifier.classify(null, PipelineBlockingException('x'));
      expect(result, isA<StructuralError>());
    });

    test('message 含 Constraint → Structural', () {
      expect(
        LlmErrorClassifier.classify(null, Exception('SQLiteException: Constraint failed')),
        isA<StructuralError>(),
      );
    });

    test('message 含 disk I/O → Structural', () {
      expect(
        LlmErrorClassifier.classify(null, Exception('disk I/O error')),
        isA<StructuralError>(),
      );
    });

    test('code 为 null（网络错误）→ Recoverable', () {
      expect(
        LlmErrorClassifier.classify(null, Exception('Connection refused')),
        isA<RecoverableError>(),
      );
    });

    test('429 → Recoverable 且携带 Retry-After', () {
      final result = LlmErrorClassifier.classify(
          429, Exception('HTTP 429 Too Many Requests — Retry-After: 30'));
      expect(result, isA<RecoverableError>());
      expect((result as RecoverableError).retryAfterSeconds, 30);
    });

    test('429 无 Retry-After → Recoverable 且 retryAfterSeconds 为 null', () {
      final result = LlmErrorClassifier.classify(429, Exception('HTTP 429'));
      expect(result, isA<RecoverableError>());
      expect((result as RecoverableError).retryAfterSeconds, isNull);
    });

    test('5xx → Recoverable', () {
      for (final code in [500, 502, 503, 599]) {
        expect(
          LlmErrorClassifier.classify(code, Exception('HTTP $code Server Error')),
          isA<RecoverableError>(),
          reason: 'code=$code',
        );
      }
    });

    test('message 含 JSON/parse/syntax → Recoverable', () {
      for (final msg in ['Invalid JSON response', 'parse error', 'syntax error']) {
        expect(
          LlmErrorClassifier.classify(null, Exception(msg)),
          isA<RecoverableError>(),
          reason: msg,
        );
      }
    });

    test('400/401/403 → LlmFatal', () {
      for (final code in [400, 401, 403]) {
        expect(
          LlmErrorClassifier.classify(code, Exception('HTTP $code')),
          isA<FatalError>(),
          reason: 'code=$code',
        );
      }
    });

    test('其他未知 code → Recoverable（保守重试）', () {
      for (final code in [404, 409, 418]) {
        expect(
          LlmErrorClassifier.classify(code, Exception('HTTP $code')),
          isA<RecoverableError>(),
          reason: 'code=$code',
        );
      }
    });
  });
}
