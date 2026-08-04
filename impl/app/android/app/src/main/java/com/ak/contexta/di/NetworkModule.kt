package com.ak.contexta.di

import com.ak.contexta.BuildConfig
import com.ak.contexta.data.remote.DeepSeekApi
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /**
     * okhttp 读超时相对协程级 LLM 超时（LLM_TIMEOUT_MS）的宽限时间。
     *
     * 背景：若两者相等（同为 300s），会形成竞态——协程的计时在请求发出前
     * 几毫秒启动，总是先触发，超时走 LlmCaller 的协程超时路径（直接放弃），
     * 而 OkHttp 的 SocketTimeoutException（可重试路径）永远没有机会触发。
     *
     * 加上宽限后：协程超时确定性地先触发 → LlmTimeoutException（LLM_TIMEOUT
     * 分类），且 withTimeoutOrNull 取消协程时底层 OkHttp 调用被同步取消，
     * 不会留下悬空的连接。
     */
    private const val READ_TIMEOUT_GRACE_MS = 60_000L

    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient {
        val loggingInterceptor = HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) {
                HttpLoggingInterceptor.Level.BODY
            } else {
                HttpLoggingInterceptor.Level.NONE
            }
        }

        return OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            // okhttp 读超时 = 协程级 LLM 超时 + 宽限（见 READ_TIMEOUT_GRACE_MS）：
            // 若 <= 协程超时，okhttp 会先超时触发重试风暴（慢响应被重复重试）；
            // 若相等则竞态（见 READ_TIMEOUT_GRACE_MS 注释）；大于时协程超时确定性胜出
            .readTimeout(BuildConfig.LLM_TIMEOUT_MS + READ_TIMEOUT_GRACE_MS, TimeUnit.MILLISECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer ${BuildConfig.DEEPSEEK_API_KEY}")
                    .addHeader("Content-Type", "application/json")
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(loggingInterceptor)
            .build()
    }

    @Provides
    @Singleton
    fun provideDeepSeekApi(okHttpClient: OkHttpClient, json: Json): DeepSeekApi {
        val baseUrl = BuildConfig.DEEPSEEK_BASE_URL.takeIf { it.isNotBlank() }
            ?: "https://api.deepseek.com/"

        val retrofit = Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttpClient)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()

        return retrofit.create(DeepSeekApi::class.java)
    }
}
