package com.ak.contexta.testing

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner

/**
 * Custom AndroidJUnitRunner that forces [TestContextaApplication_Application] as the
 * application class for instrumented tests.
 *
 * On Android 16 (API 36), the standard `androidx.test.core.app.Application` instrumentation
 * argument is not properly honored by AndroidJUnitRunner when the target APK declares
 * a @HiltAndroidApp application. This runner bypasses that by directly overriding
 * [newApplication] with the correct test application class.
 */
class ContextaTestRunner : AndroidJUnitRunner() {
    override fun newApplication(cl: ClassLoader, className: String, context: Context): Application {
        return super.newApplication(
            cl,
            "com.ak.contexta.TestContextaApplication_Application",
            context
        )
    }
}
