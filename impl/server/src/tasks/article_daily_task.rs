//! 每日文章生成任务（T9）：启动补漏（今天 + 明天）+ 每日定时（[`Config::daily_generate_hour`]
//! 点生成明天，并顺带补今天）。幂等与并发安全由 T8 `ensure_daily_generation`（预占行模式）保证。
//!
//! 时间注入设计：等待统一走可注入的 [`SleepFn`]（生产 = tokio 真实定时器，测试在暂停的
//! 虚拟时钟下用 `tokio::time::advance` 推进到配置时刻，不依赖真实等待）。
//! 客户端注入设计（审查加固）：每日循环每轮经 [`ApiFactory`] 构造 DeepSeekClient——
//! 构造失败记 error + sleep 1h 重试，任务不因构造失败永久停摆；测试注入 mock 工厂。

use crate::AppState;
use crate::config::Config;
use crate::drivers::chinadaily::{ChinadailyFetcher, NoopFetcher, SourceFetcher};
use crate::drivers::deepseek::{DeepSeekApi, DeepSeekClient};
use crate::response::AppError;
use crate::services::article_service;
use crate::tasks::SleepFn;
use chrono::{Duration, Local, Timelike};
use std::sync::Arc;

/// DeepSeek 客户端工厂：每日循环每轮构造（失败可恢复重试）；测试注入 mock 工厂。
pub type ApiFactory = Arc<dyn Fn() -> anyhow::Result<Arc<dyn DeepSeekApi>> + Send + Sync>;

/// 生产工厂：基于 cfg 构造 DeepSeekClient（构造失败由循环的 1h 重试兜底）。
pub fn production_api_factory(cfg: Arc<Config>) -> ApiFactory {
    Arc::new(move || DeepSeekClient::new(&cfg).map(|c| Arc::new(c) as Arc<dyn DeepSeekApi>))
}

/// 启动补漏：生成今天 + 明天各 15 篇（每难度 5，T8 幂等）。重复调用不新增行；
/// 失败返回 Err（由调用方决定：启动补漏失败只记日志，不阻止 serve）。
/// 今天/明天由同一次 `Local::now()` 推导（消除跨午夜窗口产生非相邻日期的可能）。
pub async fn run_startup_fill(
    state: &AppState,
    cfg: &Config,
    api: &dyn DeepSeekApi,
    fetcher: &dyn SourceFetcher,
) -> Result<(), AppError> {
    let now = Local::now();
    let today = now.format("%Y-%m-%d").to_string();
    let tomorrow = (now + Duration::days(1)).format("%Y-%m-%d").to_string();
    article_service::ensure_daily_generation(&state.pool, cfg, api, fetcher, &today).await?;
    article_service::ensure_daily_generation(&state.pool, cfg, api, fetcher, &tomorrow).await?;
    Ok(())
}

/// 每日生成循环：等待到 [`Config::daily_generate_hour`] 点（分钟=01，避开整点边界）后，
/// 每轮经工厂构造客户端（失败记 error + sleep 1h 重试），生成明天并顺带补今天——
/// 幂等、成本为零：启动补漏失败后当天缺文自动补齐（LLM 恢复后下一次 wake 即自愈）。
/// 单次生成失败只记日志，循环继续（T8 幂等自愈）。独立于启动补漏——测试可直接驱动
/// 本循环验证「到配置时刻触发且生成今天+明天」。
pub async fn daily_generation_loop(
    state: AppState,
    cfg: Arc<Config>,
    api_factory: ApiFactory,
    fetcher: Arc<dyn SourceFetcher>,
    sleep: SleepFn,
) {
    loop {
        let now = Local::now();
        let next = if now.hour() < cfg.daily_generate_hour as u32 {
            // 今天该时刻
            now.date_naive()
                .and_hms_opt(cfg.daily_generate_hour as u32, 1, 0)
                .unwrap()
        } else {
            // 明天该时刻
            (now.date_naive() + Duration::days(1))
                .and_hms_opt(cfg.daily_generate_hour as u32, 1, 0)
                .unwrap()
        };
        let wait = next - now.naive_local();
        tracing::info!("daily task: next run at {next} (in {wait})");
        sleep(wait.to_std().unwrap_or(std::time::Duration::from_secs(60))).await;
        // 每轮构造客户端：失败记 error + sleep 1h 再试（构造可恢复，任务不永久停摆）
        let api = match (api_factory)() {
            Ok(a) => a,
            Err(e) => {
                tracing::error!("daily task: deepseek client: {e}");
                sleep(std::time::Duration::from_secs(3600)).await;
                continue;
            }
        };
        // 今天/明天由同一次 now 推导；今天顺带补漏（幂等、成本为零）
        let now = Local::now();
        let today = now.format("%Y-%m-%d").to_string();
        let tomorrow = (now + Duration::days(1)).format("%Y-%m-%d").to_string();
        if let Err(e) = article_service::ensure_daily_generation(
            &state.pool,
            &cfg,
            api.as_ref(),
            fetcher.as_ref(),
            &today,
        )
        .await
        {
            tracing::error!("daily generation (today) failed: {e:?}");
        }
        if let Err(e) = article_service::ensure_daily_generation(
            &state.pool,
            &cfg,
            api.as_ref(),
            fetcher.as_ref(),
            &tomorrow,
        )
        .await
        {
            tracing::error!("daily generation failed: {e:?}");
        }
    }
}

/// 每日任务入口（main `tokio::spawn`）：启动补漏（客户端构造/生成失败仅记日志，不阻止
/// serve——本函数已在独立任务中）→ 每日循环（每轮经工厂构造客户端，构造失败可恢复）。
pub async fn spawn_daily_task(state: AppState, cfg: Arc<Config>, sleep: SleepFn) {
    // 事实源抓取器：构造失败降级 NoopFetcher（NEWS 走自由发挥，不阻断任务）
    let fetcher: Arc<dyn SourceFetcher> = match ChinadailyFetcher::new(&cfg) {
        Ok(f) => Arc::new(f),
        Err(e) => {
            tracing::error!("chinadaily fetcher: {e}");
            Arc::new(NoopFetcher)
        }
    };
    match DeepSeekClient::new(&cfg) {
        Ok(client) => {
            if let Err(e) = run_startup_fill(&state, &cfg, &client, fetcher.as_ref()).await {
                tracing::error!("daily task: startup fill failed: {e:?}");
            }
        }
        Err(e) => tracing::error!("daily task: deepseek client: {e}"),
    }
    let factory = production_api_factory(cfg.clone());
    daily_generation_loop(state, cfg, factory, fetcher, sleep).await;
}
