use server::{config, make_router};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init()
        .ok();
    let cfg = Arc::new(config::Config::load()?);
    // TODO(Task 2): db::init_pool / db::migrate / db::seed_admin 注入 AppState 后改用 build_router
    let router = make_router();
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", cfg.port)).await?;
    tracing::info!("listening on :{}", cfg.port);
    axum::serve(listener, router).await?;
    Ok(())
}
