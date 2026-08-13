pub mod config;
pub mod db;
pub mod drivers;
pub mod extractors;
pub mod jwt;
pub mod llm;
pub mod prompts;
pub mod response;
pub mod routers;
pub mod services;
// 后续任务逐步加入：tasks(T9)

use axum::Router;

#[derive(Clone)]
pub struct AppState {
    pub pool: sqlx::SqlitePool,
    pub cfg: std::sync::Arc<config::Config>,
}

/// 无状态路由（health/静态页），无 DB 依赖的测试入口。
pub fn make_router() -> Router {
    routers::no_state_routes()
}

/// 完整路由（AppState 注入）。
pub fn build_router(state: AppState) -> Router {
    routers::api_routes(state)
}
