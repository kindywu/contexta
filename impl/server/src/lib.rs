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
pub mod tasks;
// 管理页静态资源。文件名 static.rs（rust-embed 嵌入 admin-ui/dist/），
// `static` 是 Rust 关键字不能作模块名，故用 #[path] 挂 static_assets 名。
#[path = "static.rs"]
pub mod static_assets;

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
