import java.io.FileInputStream
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlin.serialization)
}

val localProperties = rootProject.file("local.properties").takeIf { it.exists() }
    ?.let { file -> Properties().also { it.load(FileInputStream(file)) } }

val deepSeekApiKey: String = localProperties?.getProperty("deepseek.apiKey") ?: ""
val deepSeekModel: String = localProperties?.getProperty("deepseek.model") ?: "deepseek-v4-flash"
val deepSeekBaseUrl: String = localProperties?.getProperty("deepseek.baseUrl") ?: "https://api.deepseek.com"
val feishuWebhookUrl: String = localProperties?.getProperty("feishu.webhookUrl") ?: ""
val feishuSignSecret: String = localProperties?.getProperty("feishu.signSecret") ?: ""
// LLM 调用超时（ms）：High 难度文章生成耗时更长，可在 local.properties 调大（llm.timeoutMs）
val llmTimeoutMs: Long = (localProperties?.getProperty("llm.timeoutMs") ?: "120000").toLong()
// LLM 可恢复错误重试次数（llm.maxRetries）
val llmMaxRetries: Int = (localProperties?.getProperty("llm.maxRetries") ?: "3").toInt()

android {
    namespace = "com.ak.contexta"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.ak.contexta"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "com.ak.contexta.testing.ContextaTestRunner"
        testInstrumentationRunnerArguments["androidx.test.core.app.Application"] =
            "com.ak.contexta.TestContextaApplication_Application"

        buildConfigField("String", "DEEPSEEK_API_KEY", "\"${deepSeekApiKey}\"")
        buildConfigField("String", "DEEPSEEK_MODEL", "\"${deepSeekModel}\"")
        buildConfigField("String", "DEEPSEEK_BASE_URL", "\"${deepSeekBaseUrl}\"")
        buildConfigField("String", "FEISHU_WEBHOOK_URL", "\"${feishuWebhookUrl}\"")
        buildConfigField("String", "FEISHU_SIGN_SECRET", "\"${feishuSignSecret}\"")
        buildConfigField("long", "LLM_TIMEOUT_MS", "${llmTimeoutMs}L")
        buildConfigField("int", "LLM_MAX_RETRIES", "$llmMaxRetries")

        testOptions {
            unitTests {
                isReturnDefaultValues = true
            }
        }
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    // Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    // Navigation
    implementation(libs.androidx.navigation.compose)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    // Room
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Retrofit + OkHttp
    implementation(libs.retrofit)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.retrofit.kotlinx.serialization)

    // WorkManager
    implementation(libs.workmanager)
    implementation(libs.hilt.work)
    ksp(libs.hilt.work.compiler)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.hilt.android.testing)
    kspAndroidTest(libs.hilt.compiler)
}
