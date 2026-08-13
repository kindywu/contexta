pub mod admin;
pub mod auth;
pub mod health;
pub mod llm;
// 后续任务逐步加入：articles(T10)；admin 用户管理/文章审核路由 T11/T12 填充

use crate::AppState;
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
        .route("/api/admin/login", axum::routing::post(admin::login))
        .route("/api/admin/users", axum::routing::get(admin::users_list))
        .route(
            "/api/llm/word-lookup",
            axum::routing::post(llm::word_lookup),
        )
        .with_state(state)
}
