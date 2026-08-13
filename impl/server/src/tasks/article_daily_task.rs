//! 每日文章生成任务（T9）：启动补漏（今天 + 明天）+ 每日定时（[`Config::daily_generate_hour`]
//! 点生成明天）。幂等与并发安全由 T8 `ensure_daily_generation`（预占行模式）保证。
//!
//! 时间注入设计：等待统一走可注入的 [`SleepFn`]（生产 = tokio 真实定时器，测试在暂停的
//! 虚拟时钟下用 `tokio::time::advance` 推进到配置时刻，不依赖真实等待）。
//!
//! 结构与简报差异（测试优先）：简报代码片段让 `run_startup_fill` 内部构造 DeepSeekClient，
//! 但其测试草图要求注入 mock API——故 `run_startup_fill` / `daily_generation_loop` 均接受
//! `&dyn DeepSeekApi`（可测），客户端由 `spawn_daily_task` 构造一次注入两端。

use crate::AppState;
use crate::config::Config;
use crate::drivers::deepseek::{DeepSeekApi, DeepSeekClient};
use crate::response::AppError;
use crate::services::article_service;
use crate::tasks::SleepFn;
use chrono::{Duration, Local, Timelike};
use std::sync::Arc;

/// 启动补漏：生成今天 + 明天各 15 篇（每难度 5，T8 幂等）。重复调用不新增行；
/// 失败返回 Err（由调用方决定：启动补漏失败只记日志，不阻止 serve）。
pub async fn run_startup_fill(
    state: &AppState,
    cfg: &Config,
    api: &dyn DeepSeekApi,
) -> Result<(), AppError> {
    let today = Local::now().format("%Y-%m-%d").to_string();
    let tomorrow = (Local::now() + Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    article_service::ensure_daily_generation(&state.pool, cfg, api, &today).await?;
    article_service::ensure_daily_generation(&state.pool, cfg, api, &tomorrow).await?;
    Ok(())
}

/// 每日生成循环：每天 [`Config::daily_generate_hour`] 点（分钟=01，避开整点边界）生成明天。
/// 独立于启动补漏——测试可直接驱动本循环验证「到配置时刻触发且 target_date=明天」；
/// 单次失败只记日志，循环继续（下一天重试，T8 幂等自愈）。
pub async fn daily_generation_loop(
    state: AppState,
    cfg: Arc<Config>,
    api: &dyn DeepSeekApi,
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
        let tomorrow = (Local::now() + Duration::days(1))
            .format("%Y-%m-%d")
            .to_string();
        if let Err(e) =
            article_service::ensure_daily_generation(&state.pool, &cfg, api, &tomorrow).await
        {
            tracing::error!("daily generation failed: {e:?}");
        }
    }
}

/// 每日任务入口（main `tokio::spawn`）：启动补漏（失败仅记日志，不阻止 serve——
/// 本函数已在独立任务中）→ 每日循环。客户端构造失败同样只记日志退出。
pub async fn spawn_daily_task(state: AppState, cfg: Arc<Config>, sleep: SleepFn) {
    let client = match DeepSeekClient::new(&cfg) {
        Ok(c) => c,
        Err(e) => {
            tracing::error!("daily task: deepseek client: {e}");
            return;
        }
    };
    if let Err(e) = run_startup_fill(&state, &cfg, &client).await {
        tracing::error!("daily task: startup fill failed: {e:?}");
    }
    daily_generation_loop(state, cfg, &client, sleep).await;
}
