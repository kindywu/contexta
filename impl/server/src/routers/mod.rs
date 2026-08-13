pub mod health;
// 后续任务逐步加入：admin(T11/T12), articles(T10), auth(T3/T4), llm(T7)

use crate::AppState;
use axum::Router;

/// 无状态路由（测试/静态页）。
pub fn no_state_routes() -> Router {
    Router::new().route("/api/health", axum::routing::get(health::health))
}

/// 完整路由（AppState 注入）。
/// 注：axum 0.8 的 merge 要求两侧状态类型一致（Router<()> 无法 merge 进 Router<AppState>），
/// 故此处直接挂路由而非 merge no_state_routes()；后续有状态路由同样直接挂在这里。
pub fn api_routes(state: AppState) -> Router {
    Router::new()
        .route("/api/health", axum::routing::get(health::health))
        .with_state(state)
}
