package com.ak.contexta.e2e

import com.ak.contexta.data.remote.DeepSeekApi
import com.ak.contexta.data.remote.dto.ChatCompletionRequest
import com.ak.contexta.data.remote.dto.ChatCompletionResponse

/**
 * Fake implementation of [DeepSeekApi] for instrumented E2E tests.
 *
 * Returns a pre-configured [response] for every [chatCompletion] call.
 * Thread-safe for use from coroutine dispatchers.
 */
class FakeDeepSeekApi : DeepSeekApi {

    /** The response to return. Set this before the API is called. */
    @Volatile
    var response: ChatCompletionResponse? = null

    /** If non-null, thrown instead of returning [response]. */
    @Volatile
    var error: Exception? = null

    /** How many times [chatCompletion] has been called. */
    @Volatile
    var callCount = 0

    override suspend fun chatCompletion(
        request: ChatCompletionRequest
    ): ChatCompletionResponse {
        callCount++
        error?.let { throw it }
        return response ?: error("FakeDeepSeekApi: no response configured. Set response before calling.")
    }
}
