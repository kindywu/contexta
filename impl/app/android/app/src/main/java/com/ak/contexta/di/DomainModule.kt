package com.ak.contexta.di

import com.ak.contexta.data.AndroidAppInfoProvider
import com.ak.contexta.data.remote.LlmCaller
import com.ak.contexta.data.time.SystemTimeProvider
import com.ak.contexta.data.tts.TtsEngineImpl
import com.ak.contexta.domain.AppInfoProvider
import com.ak.contexta.domain.BackgroundWorkScheduler
import com.ak.contexta.domain.DeveloperAlertSender
import com.ak.contexta.domain.LlmClient
import com.ak.contexta.domain.di.CoroutineDispatchers
import com.ak.contexta.domain.time.TimeProvider
import com.ak.contexta.domain.tts.TtsEngine
import com.ak.contexta.monitoring.FeishuAlertSender
import com.ak.contexta.worker.GenerationScheduler
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class DomainModule {

    @Binds abstract fun bindTimeProvider(impl: SystemTimeProvider): TimeProvider

    @Binds abstract fun bindDeveloperAlertSender(impl: FeishuAlertSender): DeveloperAlertSender

    @Binds abstract fun bindAppInfoProvider(impl: AndroidAppInfoProvider): AppInfoProvider

    @Binds abstract fun bindTtsEngine(impl: TtsEngineImpl): TtsEngine

    @Binds abstract fun bindLlmClient(impl: LlmCaller): LlmClient

    @Binds abstract fun bindBackgroundWorkScheduler(impl: GenerationScheduler): BackgroundWorkScheduler

    companion object {
        @Provides
        @Singleton
        fun provideCoroutineDispatchers(): CoroutineDispatchers = CoroutineDispatchers()
    }
}
