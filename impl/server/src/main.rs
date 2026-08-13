use server::{AppState, build_router, config, db};
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
    let router = build_router(AppState {
        pool,
        cfg: cfg.clone(),
    });
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", cfg.port)).await?;
    tracing::info!("listening on :{}", cfg.port);
    axum::serve(listener, router).await?;
    Ok(())
}
