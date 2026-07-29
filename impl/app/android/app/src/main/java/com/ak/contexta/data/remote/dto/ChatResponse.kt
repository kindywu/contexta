package com.ak.contexta.data.remote.dto

import kotlinx.serialization.Serializable

@Serializable
data class ChatCompletionResponse(
    val id: String? = null,
    val choices: List<Choice> = emptyList(),
    val usage: Usage? = null
)

@Serializable
data class Choice(
    val index: Int = 0,
    val message: ChatResponseMessage,
    val finish_reason: String? = null
)

@Serializable
data class ChatResponseMessage(
    val role: String = "assistant",
    val content: String = ""
)

@Serializable
data class Usage(
    val prompt_tokens: Int = 0,
    val completion_tokens: Int = 0,
    val total_tokens: Int = 0
)
