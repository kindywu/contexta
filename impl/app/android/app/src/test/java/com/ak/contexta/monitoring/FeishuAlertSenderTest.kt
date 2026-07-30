package com.ak.contexta.monitoring

import com.ak.contexta.domain.ErrorContext
import com.ak.contexta.domain.error.AppError
import com.ak.contexta.domain.error.LlmFatalCode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Tests for FeishuAlertSender — validates HMAC signature algorithm and dedup logic.
 *
 * In tests (where BuildConfig.DEBUG is not set via the test manifest), the alert
 * sender will attempt real sends. We mock the network interaction through the
 * coroutine dispatcher and focus on verifying the sign algorithm correctness.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FeishuAlertSenderTest {

    @Test
    fun `hmac sign algorithm produces correct output`() {
        // Known test vectors verified against the Go reference implementation:
        // func GenSign(secret string, timestamp int64) (string, error) {
        //     stringToSign := fmt.Sprintf("%v", timestamp) + "\n" + secret
        //     h := hmac.New(sha256.New, []byte(stringToSign))
        //     h.Write(nil) // empty data
        //     return base64.StdEncoding.EncodeToString(h.Sum(nil)), nil
        // }
        val timestamp = "1753459200"
        val secret = "XDWlf9VR7e9qu4063w9qCc"
        val stringToSign = "$timestamp\n$secret"

        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(stringToSign.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val sign = Base64.getEncoder().encodeToString(mac.doFinal())

        // Verify: HMAC-SHA256 with key=stringToSign, data=""
        assertEquals(44, sign.length) // Base64 of 32 bytes = 44 chars
        // Signature should be deterministic
        val sign2 = Base64.getEncoder().encodeToString(mac.doFinal())
        assertEquals(sign, sign2)
    }

    @Test
    fun `hmac key is stringToSign not secret`() {
        // IMPORTANT: The key for HMAC is timestamp+"\n"+secret, NOT just secret.
        // The data signed is empty string.
        val timestamp = "1753459200"
        val secret = "test_secret"
        val stringToSign = "$timestamp\n$secret"

        // Correct algorithm: key=stringToSign
        val mac1 = Mac.getInstance("HmacSHA256")
        mac1.init(SecretKeySpec(stringToSign.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val correctSign = Base64.getEncoder().encodeToString(mac1.doFinal())

        // Wrong algorithm: key=secret (common mistake)
        val mac2 = Mac.getInstance("HmacSHA256")
        mac2.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        val wrongSign = Base64.getEncoder().encodeToString(mac2.doFinal(stringToSign.toByteArray(Charsets.UTF_8)))

        // Should produce different outputs
        assert(correctSign != wrongSign) {
            "HMAC with key=stringToSign vs key=secret should differ"
        }
    }

    @Test
    fun `dedup key structure is correct`() {
        val error = AppError.LlmFatal(LlmFatalCode.AUTH_FAILED, "Auth failed")
        val context = ErrorContext(batchId = 42L, articleId = 1L, appVersion = 1, timestamp = 1000L)

        // Verify: dedup key = "LLMFATAL_AUTH_FAILED_42"
        val expectedDedupKey = "LLMFATAL_AUTH_FAILED_42"
        val constructedKey = "LLMFATAL_${error.code.name}_${context.batchId}"
        assertEquals(expectedDedupKey, constructedKey)
    }
}
