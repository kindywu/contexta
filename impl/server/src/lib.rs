pub mod config;
pub mod response;
pub mod routers;
// 后续任务逐步加入：jwt(T3), extractors(T3), db(T2), drivers(T5), prompts(T6), llm(T5/T7), services(T8), tasks(T9)

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
