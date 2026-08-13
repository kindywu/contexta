pub mod auth;
pub mod health;
// 后续任务逐步加入：admin(T11/T12), articles(T10), llm(T7)

use crate::AppState;
use crate::services;
use axum::Router;

/// 无状态路由（测试/静态页）。泛型化：Router<S> 的 S 在 merge 前保持自由，
/// 供 api_routes 在注入 AppState 后统一，避免复制路由源。
pub fn no_state_routes<S: Clone + Send + Sync + 'static>() -> Router<S> {
    Router::new().route("/api/health", axum::routing::get(health::health))
}

/// 完整路由（AppState 注入）。
pub fn api_routes(state: AppState) -> Router {
    Router::new()
        .merge(no_state_routes())
        .route("/api/auth/login", axum::routing::post(auth::login))
        .route("/api/auth/logout", axum::routing::post(auth::logout))
        .route("/api/auth/me", axum::routing::get(auth::me))
        .with_state(state)
}
