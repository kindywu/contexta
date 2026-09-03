import 'package:flutter_test/flutter_test.dart';

import 'package:contexta/domain/error/app_error.dart';
import 'package:contexta/domain/error/domain_result.dart';
import 'package:contexta/domain/error/llm_exceptions.dart';
import 'package:contexta/domain/error/pipeline_blocking_exception.dart';

/// 对照 Kotlin domain/error/*.kt（AppError.kt / DomainResult.kt /
/// LlmExceptions.kt / PipelineBlockingException.kt）。
void main() {
  group('AppError 层级', () {
    test('Recoverable 携带 code/message/cause/retryAfterSeconds', () {
      final e = Recoverable(
        code: RecoverableCode.rateLimited,
        message: '429 Too Many Requests',
        retryAfterSeconds: 30,
      );
      expect(e, isA<AppError>());
      expect(e.code, RecoverableCode.rateLimited);
      expect(e.message, '429 Too Many Requests');
      expect(e.cause, isNull);
      expect(e.retryAfterSeconds, 30);
      expect(Recoverable(
        code: RecoverableCode.networkTimeout,
        message: 'timeout',
      ).retryAfterSeconds, isNull);
    });

    test('LlmFatal 携带 code/message/cause', () {
      final e = LlmFatal(
        code: LlmFatalCode.authFailed,
        message: '401 Unauthorized',
      );
      expect(e, isA<AppError>());
      expect(e.code, LlmFatalCode.authFailed);
      expect(e.message, '401 Unauthorized');
      expect(e.cause, isNull);
    });

    test('Structural 携带 code/message/cause', () {
      final cause = StateError('inner');
      final e = Structural(
        code: StructuralCode.dbConstraintViolation,
        message: 'DB constraint violated',
        cause: cause,
      );
      expect(e, isA<AppError>());
      expect(e.code, StructuralCode.dbConstraintViolation);
      expect(e.message, 'DB constraint violated');
      expect(e.cause, same(cause));
    });

    test('when 穷举可判别三类（无 default 分支）', () {
      String label(AppError err) => switch (err) {
            Recoverable() => 'recoverable',
            LlmFatal() => 'llmFatal',
            Structural() => 'structural',
          };

      expect(label(Recoverable(code: RecoverableCode.serverError, message: 'x')),
          'recoverable');
      expect(label(LlmFatal(code: LlmFatalCode.contentPolicy, message: 'x')),
          'llmFatal');
      expect(label(Structural(code: StructuralCode.serializationError, message: 'x')),
          'structural');
    });

    test('错误码字符串与 Kotlin Enum.name 一致', () {
      expect(RecoverableCode.networkTimeout.toDbValue(), 'NETWORK_TIMEOUT');
      expect(RecoverableCode.rateLimited.toDbValue(), 'RATE_LIMITED');
      expect(RecoverableCode.serverError.toDbValue(), 'SERVER_ERROR');
      expect(RecoverableCode.jsonParseFailed.toDbValue(), 'JSON_PARSE_FAILED');
      expect(RecoverableCode.llmTimeout.toDbValue(), 'LLM_TIMEOUT');

      expect(LlmFatalCode.authFailed.toDbValue(), 'AUTH_FAILED');
      expect(LlmFatalCode.badRequest.toDbValue(), 'BAD_REQUEST');
      expect(LlmFatalCode.contentPolicy.toDbValue(), 'CONTENT_POLICY');
      expect(LlmFatalCode.emptyResponse.toDbValue(), 'EMPTY_RESPONSE');

      expect(StructuralCode.dbConstraintViolation.toDbValue(),
          'DB_CONSTRAINT_VIOLATION');
      expect(StructuralCode.serializationError.toDbValue(),
          'SERIALIZATION_ERROR');
      expect(StructuralCode.diskIoError.toDbValue(), 'DISK_IO_ERROR');
      expect(StructuralCode.illegalState.toDbValue(), 'ILLEGAL_STATE');
      expect(StructuralCode.unexpectedError.toDbValue(), 'UNEXPECTED_ERROR');
    });
  });

  group('DomainResult', () {
    test('Success 分支：isSuccess / dataOrNull / errorOrNull', () {
      final r = Success(42);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);
      expect(r.dataOrNull, 42);
      expect(r.errorOrNull, isNull);
    });

    test('Failure 分支：isFailure / dataOrNull / errorOrNull', () {
      final err = Structural(
        code: StructuralCode.unexpectedError,
        message: 'boom',
      );
      final r = Failure(err);
      expect(r.isSuccess, false);
      expect(r.isFailure, true);
      expect(r.dataOrNull, isNull);
      expect(r.errorOrNull, same(err));
    });

    test('onSuccess 触发并返回自身；Failure 上不触发', () {
      final r = Success(7);
      int? got;
      final back = r.onSuccess((data) => got = data);
      expect(got, 7);
      expect(back, same(r));

      int? got2;
      DomainResult<int> f = Failure(
        Structural(code: StructuralCode.unexpectedError, message: 'x'),
      );
      f.onSuccess((data) => got2 = data);
      expect(got2, isNull);
    });

    test('onFailure 触发并返回自身；Success 上不触发', () {
      final err = LlmFatal(code: LlmFatalCode.authFailed, message: 'x');
      AppError? got;
      final r = Failure(err);
      final back = r.onFailure((e) => got = e);
      expect(got, same(err));
      expect(back, same(r));

      AppError? got2;
      Success(1).onFailure((e) => got2 = e);
      expect(got2, isNull);
    });

    test('泛型数据透传（非数值类型）', () {
      final r = Success('hello');
      expect(r.dataOrNull, 'hello');
    });
  });

  group('LLM 异常 message 透传', () {
    test('LlmFatalException', () {
      final e = LlmFatalException('Non-recoverable LLM error: 401');
      expect(e, isA<Exception>());
      expect(e.message, 'Non-recoverable LLM error: 401');
    });

    test('LlmTimeoutException', () {
      final e = LlmTimeoutException('LLM call exceeded total time budget');
      expect(e, isA<Exception>());
      expect(e.message, 'LLM call exceeded total time budget');
    });

    test('LlmRecoverableExhaustedException：attempts 默认 0 可覆盖', () {
      final e = LlmRecoverableExhaustedException('retries exhausted',
          attempts: 3);
      expect(e, isA<Exception>());
      expect(e.message, 'retries exhausted');
      expect(e.attempts, 3);
      expect(LlmRecoverableExhaustedException('x').attempts, 0);
    });

    test('cause 透传', () {
      final cause = StateError('inner');
      final e = LlmFatalException('outer', cause: cause);
      expect(e.cause, same(cause));
    });
  });

  group('PipelineBlockingException', () {
    test('message 原样保留（查词/加词调用点经 mapErrorCodeToException 展示）',
        () {
      const msg1 = 'Structural error: DB Constraint violation';
      final e1 = PipelineBlockingException(msg1);
      expect(e1.message, msg1);
      expect(e1.message.contains('Constraint'), true);

      const msg2 = 'Structural error: sqlite3 disk I/O error';
      final e2 = PipelineBlockingException(msg2);
      expect(e2.message, msg2);
      expect(e2.message.contains('disk I/O'), true);
    });

    test('cause 透传', () {
      final cause = StateError('inner');
      final e = PipelineBlockingException('boom', cause: cause);
      expect(e.cause, same(cause));
    });
  });
}
