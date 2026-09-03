import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── 构建期配置注入（DEEPSEEK 密钥等，镜像 Android 原版 build.gradle.kts） ───
// 密钥等敏感配置放在 android/local.properties（已 gitignore，不提交仓库），
// 打包时以 --dart-define 语义注入编译期常量（AppConfig.deepSeekApiKey 等）。
// 编码与 flutter 工具 encodeDartDefines 一致：base64(utf8("NAME=value"))，逗号分隔。
plugins.withId("dev.flutter.flutter-gradle-plugin") {
    // 读取 android/local.properties（不存在或字段缺失时静默跳过注入）
    val props = Properties()
    file("../local.properties").takeIf { it.exists() }?.inputStream()?.use { props.load(it) }

    // 收集注入项：key → 配置值；值为空则不注入（保持编译期默认值）
    val injected = listOfNotNull(
        "DEEPSEEK_API_KEY" to (props.getProperty("deepseek.apiKey") ?: ""),
        "DEEPSEEK_MODEL" to (props.getProperty("deepseek.model") ?: ""),
        "DEEPSEEK_BASE_URL" to (props.getProperty("deepseek.baseUrl") ?: ""),
        "FEISHU_WEBHOOK_URL" to (props.getProperty("feishu.webhookUrl") ?: ""),
        "FEISHU_SIGN_SECRET" to (props.getProperty("feishu.signSecret") ?: ""),
    ).filter { it.second.isNotBlank() }

    fun String.b64(): String = Base64.getEncoder().encodeToString(toByteArray(Charsets.UTF_8))

    // 与命令行 --dart-define 合并：CLI 提供的同名 key 优先（不重复注入）
    val cliRaw = (findProperty("dart-defines") as String? ?: "")
    val existingKeys = cliRaw.split(",")
        .filter { it.isNotBlank() }
        .map { String(Base64.getDecoder().decode(it)).substringBefore("=") }
        .toMutableSet()

    val merged = buildList {
        addAll(cliRaw.split(",").filter { it.isNotBlank() })
        for ((key, value) in injected) {
            if (existingKeys.add(key)) add("$key=$value".b64())
        }
    }
    if (merged.isNotEmpty()) {
        ext["dart-defines"] = merged.joinToString(",")
    }
}

android {
    namespace = "com.ak.contexta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ak.contexta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // v2 并行安装（2026-08-14）：debug 构建使用独立 applicationId
            // （com.ak.contexta.v2），与旧版包并存互不干扰，adb install -r 不触碰旧包；
            // release 保持 com.ak.contexta。
            applicationIdSuffix = ".v2"
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 混淆 onnxruntime 的 JNI 类会导致原生崩溃（SIGABRT），
            // keep 规则见 proguard-rules.pro
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
