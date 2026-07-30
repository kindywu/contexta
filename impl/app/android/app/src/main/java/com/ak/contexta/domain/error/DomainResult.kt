package com.ak.contexta.domain.error

/**
 * 同步操作的统一返回类型，用于 Use Case 和 Repository 方法。
 * ViewModel 根据结果转为 UI 状态（Snackbar、Dialog 等）。
 */
sealed class DomainResult<out T> {
    data class Success<T>(val data: T) : DomainResult<T>()
    data class Failure(val error: AppError) : DomainResult<Nothing>()

    val isSuccess: Boolean get() = this is Success
    val isFailure: Boolean get() = this is Failure

    fun getOrNull(): T? = when (this) {
        is Success -> data
        is Failure -> null
    }

    fun errorOrNull(): AppError? = when (this) {
        is Success -> null
        is Failure -> error
    }

    inline fun onSuccess(action: (T) -> Unit): DomainResult<T> {
        if (this is Success) action(data)
        return this
    }

    inline fun onFailure(action: (AppError) -> Unit): DomainResult<T> {
        if (this is Failure) action(error)
        return this
    }
}
