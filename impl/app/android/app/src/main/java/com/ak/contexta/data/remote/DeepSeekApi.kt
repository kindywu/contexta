package com.ak.contexta.data.remote

import com.ak.contexta.data.remote.dto.ChatCompletionRequest
import com.ak.contexta.data.remote.dto.ChatCompletionResponse
import retrofit2.http.Body
import retrofit2.http.POST

interface DeepSeekApi {
    @POST("v1/chat/completions")
    suspend fun chatCompletion(@Body request: ChatCompletionRequest): ChatCompletionResponse
}
