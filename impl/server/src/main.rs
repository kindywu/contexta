use server::{AppState, build_router, config, db, tasks};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init()
        .ok();
    let cfg = Arc::new(config::Config::load()?);
    let pool = db::init_pool(&cfg.db_path).await?;
    db::migrate(&pool).await?;
    if let Some(password) = &cfg.admin_init_password {
        db::seed_admin(&pool, password).await?;
    }
    let state = AppState {
        pool,
        cfg: cfg.clone(),
    };
    let router = build_router(state.clone());
    // 每日生成任务（T9）：启动补漏（今天+明天）+ 每天 config.daily_generate_hour 点生成明天。
    // 独立任务：失败只记日志，不影响 serve。句柄丢弃即 detach（进程生命周期内持续运行）。
    let _daily_task = tokio::spawn(tasks::article_daily_task::spawn_daily_task(
        state.clone(),
        cfg.clone(),
        tasks::default_sleep(),
    ));
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", cfg.port)).await?;
    tracing::info!("listening on :{}", cfg.port);
    axum::serve(listener, router).await?;
    Ok(())
}
