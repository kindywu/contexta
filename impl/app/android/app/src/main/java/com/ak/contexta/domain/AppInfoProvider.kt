package com.ak.contexta.domain

/**
 * 提供应用元信息，供错误上报使用。
 * 接口在 domain，实现在 data/（通过 BuildConfig 和 android.os.Build 取值）。
 */
interface AppInfoProvider {
    /** 应用版本号（versionCode） */
    val versionCode: Int

    /** 应用版本名（versionName） */
    val versionName: String

    /** 设备型号（如 "Xiaomi 14"） */
    val deviceModel: String
}
