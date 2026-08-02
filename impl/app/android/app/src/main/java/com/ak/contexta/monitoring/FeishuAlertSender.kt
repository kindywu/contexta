package com.ak.contexta.monitoring

import android.util.Log
import com.ak.contexta.BuildConfig
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.ErrorContext
import com.ak.contexta.domain.di.CoroutineDispatchers
import com.ak.contexta.domain.error.AppError
import com.ak.contexta.domain.time.TimeProvider
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FeishuAlertSender @Inject constructor(
    private val dispatchers: CoroutineDispatchers,
    private val timeProvider: TimeProvider
) : DeveloperAlertSender {

    companion object {
        private const val TAG = "FeishuAlertSender"
        private const val DEDUP_WINDOW_MS = 5 * 60 * 1000L
    }

    private val lastSentMap = mutableMapOf<String, Long>()

    override suspend fun sendLlmFatalError(error: AppError.LlmFatal, context: ErrorContext): Boolean =
        sendError(
            dedupPrefix = "LLMFATAL",
            errorCode = error.code.name,
            errorMessage = error.message,
            context = context,
            title = "🔴 Contexta LLM Fatal Error",
            templateColor = "red"
        )

    override suspend fun sendStructuralError(error: AppError.Structural, context: ErrorContext): Boolean =
        sendError(
            dedupPrefix = "STRUCTURAL",
            errorCode = error.code.name,
            errorMessage = error.message,
            context = context,
            title = "⚠️ Contexta Structural Error",
            templateColor = "red"
        )

    override suspend fun sendArticleFailure(
        status: String,
        errorCode: String,
        errorMessage: String,
        context: ErrorContext
    ): Boolean =
        // 5 分钟内同 batch + 同 errorCode 去重，避免刷屏
        sendError(
            dedupPrefix = "ARTICLE_${status}",
            errorCode = errorCode,
            errorMessage = errorMessage,
            context = context,
            title = "🟡 Contexta Article $status",
            templateColor = "orange"
        )

    override suspend fun sendBatchReady(
        batchId: Long,
        articleCount: Int,
        batchGeneratedOn: String?,
        batchDifficulty: String?,
        context: ErrorContext
    ): Boolean =
        // 批次完成通知不做去重——每个批次只发一次（重复补发由 ready_notified_at 幂等标记防住）
        sendSuccess(
            title = "🟢 Contexta Batch Ready",
            batchId = batchId,
            articleCount = articleCount,
            batchGeneratedOn = batchGeneratedOn,
            batchDifficulty = batchDifficulty,
            context = context
        )

    private suspend fun sendSuccess(
        title: String,
        batchId: Long,
        articleCount: Int,
        batchGeneratedOn: String?,
        batchDifficulty: String?,
        context: ErrorContext
    ): Boolean = withContext(dispatchers.io) {
        try {
            val message = buildFeishuSuccessCard(
                title, batchId, articleCount, batchGeneratedOn, batchDifficulty, context
            )
            sendToFeishu(message)
            Log.i(TAG, "Success alert sent: batch=$batchId, articles=$articleCount, generatedOn=$batchGeneratedOn, difficulty=$batchDifficulty")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send success alert", e)
            false
        }
    }

    private suspend fun sendError(
        dedupPrefix: String,
        errorCode: String,
        errorMessage: String,
        context: ErrorContext,
        title: String,
        templateColor: String
    ): Boolean {
        val dedupKey = "${dedupPrefix}_${errorCode}_${context.batchId}"
        val lastSent = lastSentMap[dedupKey]
        if (lastSent != null && timeProvider.nowMillis() - lastSent < DEDUP_WINDOW_MS) {
            // 去重命中 = 该告警近期已发过，视为已通知
            return true
        }

        return withContext(dispatchers.io) {
            try {
                val message = buildFeishuCardMessage(title, templateColor, errorCode, errorMessage, context)
                sendToFeishu(message)
                lastSentMap[dedupKey] = timeProvider.nowMillis()
                Log.i(TAG, "Alert sent: $dedupKey")
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send alert", e)
                false
            }
        }
    }

    private fun buildFeishuCardMessage(
        title: String,
        templateColor: String,
        errorCode: String,
        errorMessage: String,
        context: ErrorContext
    ): String {
        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
        val timeStr = dateFormat.format(java.util.Date(context.timestamp))

        val card = JSONObject().apply {
            put("msg_type", "interactive")
            put("card", JSONObject().apply {
                put("header", JSONObject().apply {
                    put("title", JSONObject().apply {
                        put("tag", "plain_text")
                        put("content", title)
                    })
                    put("template", templateColor)
                })
                put("elements", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**错误码：**$errorCode")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**消息：**${errorMessage.take(500)}")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**App 版本：**${context.appVersion}")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**Batch ID：**${context.batchId ?: "N/A"}")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**Article ID：**${context.articleId ?: "N/A"}")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**时间：**$timeStr")
                        })
                    })
                })
            })
        }
        return card.toString()
    }

    private fun buildFeishuSuccessCard(
        title: String,
        batchId: Long,
        articleCount: Int,
        batchGeneratedOn: String?,
        batchDifficulty: String?,
        context: ErrorContext
    ): String {
        val dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.getDefault())
        val timeStr = dateFormat.format(java.util.Date(context.timestamp))

        val card = JSONObject().apply {
            put("msg_type", "interactive")
            put("card", JSONObject().apply {
                put("header", JSONObject().apply {
                    put("title", JSONObject().apply {
                        put("tag", "plain_text")
                        put("content", title)
                    })
                    put("template", "green")
                })
                put("elements", org.json.JSONArray().apply {
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**${batchGeneratedOn ?: "?"} · ${batchDifficulty ?: "?"} 批次已完成：**${articleCount} 篇文章生成成功")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**Batch ID：**$batchId")
                        })
                    })
                    put(JSONObject().apply {
                        put("tag", "div")
                        put("text", JSONObject().apply {
                            put("tag", "lark_md")
                            put("content", "**时间：**$timeStr")
                        })
                    })
                })
            })
        }
        return card.toString()
    }

    private fun sendToFeishu(message: String) {
        val url = BuildConfig.FEISHU_WEBHOOK_URL
        if (url.isEmpty()) {
            Log.w(TAG, "Alert not sent: FEISHU_WEBHOOK_URL not configured")
            return
        }

        // 减 30 秒缓冲，防止设备时钟比飞书服务器快导致 timestamp 被拒
        val timestamp = (timeProvider.nowMillis() / 1000 - 30).toString()
        val secret = BuildConfig.FEISHU_SIGN_SECRET
        if (secret.isEmpty()) {
            Log.w(TAG, "Alert not sent: FEISHU_SIGN_SECRET not configured")
            return
        }

        val sign = generateSign(timestamp, secret)
        // ⚠️ base64 签名可能含 +（也可能含 /），拼进 URL query 必须 URL 编码：
        // 飞书按 URL 标准把 + 解码为空格，未编码的签名会被破坏 → 19021 sign match fail
        val encodedSign = java.net.URLEncoder.encode(sign, "UTF-8")
        val fullUrl = "${url}?timestamp=${timestamp}&sign=${encodedSign}"
        Log.i(TAG, "Sending to Feishu: $url, timestamp=$timestamp, sign=${sign.take(8)}...")

        val connection = URL(fullUrl).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.setRequestProperty("Content-Type", "application/json")
        connection.doOutput = true
        connection.outputStream.use { os ->
            os.write(message.toByteArray(Charsets.UTF_8))
        }
        val responseCode = connection.responseCode
        val responseBody = if (responseCode in 200..299) {
            connection.inputStream.bufferedReader().readText()
        } else {
            connection.errorStream?.bufferedReader()?.readText() ?: "(no body)"
        }
        Log.i(TAG, "Feishu response: code=$responseCode, body=$responseBody")
        if (responseCode !in 200..299) {
            throw java.io.IOException("Feishu API returned $responseCode: $responseBody")
        }
        // ⚠️ 飞书 Webhook 业务失败时 HTTP 仍返回 200，必须解析响应体的业务 code：
        // code != 0（如 19021 签名失败 / 19001 参数错误）视为发送失败，抛异常
        // → 调用方返回 false → 不回写 notified_at → 下次启动补发重试
        val businessCode = parseBusinessCode(responseBody)
        if (businessCode != null && businessCode != 0) {
            throw java.io.IOException(
                "Feishu business error code=$businessCode, body=$responseBody"
            )
        }
    }

    private fun parseBusinessCode(responseBody: String): Int? = try {
        JSONObject(responseBody).optInt("code", -1).takeIf { it >= 0 }
    } catch (e: Exception) {
        // 非 JSON 响应体（如网络代理拦截页），无法解析业务码 → 交给 HTTP 状态码判断
        null
    }

    /**
     * 飞书签名算法：
     * 1. stringToSign = timestamp + "\n" + secret
     * 2. 以 stringToSign 为密钥，对空字符串做 HMAC-SHA256
     * 3. Base64 编码结果
     *
     * ⚠️ key=stringToSign, data=""（非直觉：timestamp+secret 是密钥而非数据）
     */
    private fun generateSign(timestamp: String, secret: String): String {
        val stringToSign = "$timestamp\n$secret"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(stringToSign.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return Base64.getEncoder().encodeToString(mac.doFinal())
    }
}
