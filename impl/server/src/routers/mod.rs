pub mod admin;
pub mod articles;
pub mod auth;
pub mod health;
pub mod llm;

use crate::static_assets;

use crate::AppState;
use axum::Router;

/// 无状态路由（测试/静态页）。泛型化：Router<S> 的 S 在 merge 前保持自由，
/// 供 api_routes 在注入 AppState 后统一，避免复制路由源。
pub fn no_state_routes<S: Clone + Send + Sync + 'static>() -> Router<S> {
    Router::new()
        .route("/api/health", axum::routing::get(health::health))
        // 管理页静态资源（rust-embed 嵌入 admin-ui/dist/）。/admin 与 /admin/{*path}
        // 双挂：axum 0.8 的 {*path} 通配可匹配空段，但显式 /admin 更稳，SPA 路由回退 index.html。
        .route("/admin", axum::routing::get(static_assets::serve_admin))
        .route(
            "/admin/{*path}",
            axum::routing::get(static_assets::serve_admin),
        )
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
            "/api/admin/users/{phone}/ban",
            axum::routing::post(admin::ban),
        )
        .route(
            "/api/admin/users/{phone}/unban",
            axum::routing::post(admin::unban),
        )
        .route(
            "/api/admin/users/{phone}/quota",
            axum::routing::put(admin::set_quota),
        )
        .route("/api/admin/usage", axum::routing::get(admin::usage))
        .route(
            "/api/admin/articles",
            axum::routing::get(admin::articles_list),
        )
        .route(
            "/api/admin/articles/{id}",
            axum::routing::get(admin::articles_get).put(admin::article_edit),
        )
        .route(
            "/api/admin/articles/{id}/approve",
            axum::routing::post(admin::articles_approve),
        )
        .route(
            "/api/admin/articles/{id}/reject",
            axum::routing::post(admin::articles_reject),
        )
        .route(
            "/api/admin/articles/generate",
            axum::routing::post(admin::articles_generate),
        )
        .route(
            "/api/llm/word-lookup",
            axum::routing::post(llm::word_lookup),
        )
        .route("/api/articles/today", axum::routing::get(articles::today))
        .route("/api/articles", axum::routing::get(articles::by_date))
        .with_state(state)
}
