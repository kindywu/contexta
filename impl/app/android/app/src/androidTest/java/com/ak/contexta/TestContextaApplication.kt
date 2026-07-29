package com.ak.contexta

import android.app.Application
import dagger.hilt.android.testing.CustomTestApplication

/**
 * Custom Hilt test application generated for instrumented tests.
 *
 * This replaces the production @HiltAndroidApp ContextaApplication, allowing
 * @HiltAndroidTest tests to run without the "cannot use a @HiltAndroidApp application" error.
 */
@CustomTestApplication(Application::class)
class TestContextaApplication
