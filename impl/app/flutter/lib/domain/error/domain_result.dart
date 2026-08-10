import 'app_error.dart';

/// 同步操作的统一返回类型（对齐 Kotlin DomainResult.kt），
/// 用于 Use Case 和 Repository 方法。UI 根据结果转为界面状态
/// （Snackbar、Dialog 等）。
///
/// Kotlin 中为 sealed class（非 stdlib Result），Dart 对应 sealed class。
sealed class DomainResult<T> {
  const DomainResult();

  bool get isSuccess => switch (this) {
        Success<T>() => true,
        Failure() => false,
      };

  bool get isFailure => !isSuccess;

  /// 成功时返回数据，失败返回 null（对齐 Kotlin `getOrNull()`）。
  T? get dataOrNull => switch (this) {
        Success<T>(:final data) => data,
        Failure() => null,
      };

  /// 失败时返回错误，成功返回 null（对齐 Kotlin `errorOrNull()`）。
  AppError? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure(:final error) => error,
      };

  /// 成功时执行 [action]，返回自身便于链式调用。
  DomainResult<T> onSuccess(void Function(T data) action) {
    if (this case Success<T>(:final data)) action(data);
    return this;
  }

  /// 失败时执行 [action]，返回自身便于链式调用。
  DomainResult<T> onFailure(void Function(AppError error) action) {
    if (this case Failure(:final error)) action(error);
    return this;
  }
}

/// 成功分支，携带泛型数据。
class Success<T> extends DomainResult<T> {
  final T data;

  const Success(this.data);
}

/// 失败分支，携带 [AppError]（对齐 Kotlin `DomainResult<Nothing>`）。
class Failure extends DomainResult<Never> {
  final AppError error;

  const Failure(this.error);
}
