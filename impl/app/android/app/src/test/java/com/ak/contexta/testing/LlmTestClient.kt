package com.ak.contexta.testing

import com.ak.contexta.data.remote.DeepSeekApi
import com.ak.contexta.data.remote.dto.ChatCompletionRequest
import com.ak.contexta.data.remote.dto.ChatMessage
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import java.io.File
import java.io.FileInputStream
import java.util.Properties
import java.util.concurrent.TimeUnit

/**
 * Test helper for making direct LLM API calls — no mocking, no Hilt, no BuildConfig.
 *
 * Reads API credentials from `local.properties` so tests can call the real DeepSeek API.
 * This is NOT suitable for production code; it exists solely to verify that the prompt
 * builders and response parsers produce and consume valid LLM output.
 *
 * Prerequisite: a `local.properties` file in the project root with:
 *   deepseek.apiKey=sk-...
 *   deepseek.model=deepseek-v4-flash
 *   deepseek.baseUrl=https://api.deepseek.com
 */
class LlmTestClient {

    private val properties: Properties = loadProperties()

    val model: String = properties.getProperty("deepseek.model", "deepseek-v4-flash")

    private val apiKey: String = properties.getProperty("deepseek.apiKey", "")
        .also { require(it.isNotBlank()) { "deepseek.apiKey not found in local.properties — cannot call LLM" } }

    private val api: DeepSeekApi = createApi()

    private fun loadProperties(): Properties {
        val cwd = File(System.getProperty("user.dir") ?: ".")
        val propsFile = generateSequence(cwd) { it.parentFile }
            .map { File(it, "local.properties") }
            .firstOrNull { it.exists() }
            ?: throw IllegalStateException(
                "local.properties not found from ${cwd.absolutePath}. " +
                    "Ensure it exists in the project root with deepseek.apiKey set."
            )
        return Properties().also { it.load(FileInputStream(propsFile)) }
    }

    private fun createApi(): DeepSeekApi {
        val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        val client = OkHttpClient.Builder()
            .connectTimeout(60, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .build()
                chain.proceed(request)
            }
            .build()

        val baseUrl = properties.getProperty("deepseek.baseUrl", "https://api.deepseek.com")

        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()

        return retrofit.create(DeepSeekApi::class.java)
    }

    /**
     * Call the LLM with the given system and user prompts.
     * Returns the raw response text from the model.
     */
    suspend fun call(systemPrompt: String, userPrompt: String): String {
        val request = ChatCompletionRequest(
            model = model,
            messages = listOf(
                ChatMessage(role = "system", content = systemPrompt),
                ChatMessage(role = "user", content = userPrompt)
            )
        )
        val response = api.chatCompletion(request)
        return response.choices.firstOrNull()?.message?.content
            ?: throw IllegalStateException("Empty response from LLM — no choices returned")
    }
}
