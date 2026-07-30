package com.ak.contexta.data

import android.os.Build
import com.ak.contexta.BuildConfig
import com.ak.contexta.domain.AppInfoProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * [AppInfoProvider] 的生产实现，基于 Android BuildConfig 和系统 API。
 */
@Singleton
class AndroidAppInfoProvider @Inject constructor() : AppInfoProvider {
    override val versionCode: Int get() = BuildConfig.VERSION_CODE
    override val versionName: String get() = BuildConfig.VERSION_NAME
    override val deviceModel: String get() = "${Build.MANUFACTURER} ${Build.MODEL}"
}
