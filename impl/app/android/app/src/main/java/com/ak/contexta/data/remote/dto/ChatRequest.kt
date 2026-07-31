package com.ak.contexta.data.remote.dto

import kotlinx.serialization.Serializable

@Serializable
data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>,
    val temperature: Double = 0.7,
    val max_tokens: Int = 16384,
    val stream: Boolean = false
)

@Serializable
data class ChatMessage(
    val role: String, // "system" | "user" | "assistant"
    val content: String
)
