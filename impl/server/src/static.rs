//! 管理页静态资源（rust-embed 编译期嵌入 admin-ui/dist/）。
//!
//! 编译前提：`cd admin-ui && npm run build` 产出 dist/ 后再编译本 crate——
//! RustEmbed derive 在编译期读取 `admin-ui/dist/`，目录缺失则编译失败。
//! dist/ 已提交仓库，保证任何检出都能编译（免 node 环境）。

use axum::http::StatusCode;
use axum::http::{Uri, header};
use axum::response::{IntoResponse, Response};
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "admin-ui/dist/"]
struct AdminAssets;

/// 服务 /admin 与 /admin/{*path}：命中文件原样返回（按扩展名猜 MIME），
/// 未命中回退 index.html（SPA 前端路由），dist 缺失时 404 提示未构建。
///
/// 缓存策略：index.html 返回 `Cache-Control: no-cache`（强制每次重新校验，
/// 防止浏览器缓存旧 bundle 导致「页面与新后端不匹配」）；哈希命名的
/// 静态资源（assets/*.js/css）默认强缓存（文件名带哈希，内容不可变）。
pub async fn serve_admin(uri: Uri) -> Response {
    let path = uri.path().trim_start_matches("/admin/").to_string();
    let is_index = path.is_empty() || path == "index.html";
    let path = if path.is_empty() { "index.html" } else { &path };
    match AdminAssets::get(path) {
        Some(f) => {
            let mime = mime_guess::from_path(path).first_or_octet_stream();
            if is_index {
                (
                    [
                        (header::CONTENT_TYPE, mime.as_ref()),
                        (header::CACHE_CONTROL, "no-cache"),
                    ],
                    f.data.into_owned(),
                )
                    .into_response()
            } else {
                ([(header::CONTENT_TYPE, mime.as_ref())], f.data.into_owned()).into_response()
            }
        }
        None => match AdminAssets::get("index.html") {
            Some(f) => (
                [
                    (header::CONTENT_TYPE, "text/html"),
                    (header::CACHE_CONTROL, "no-cache"),
                ],
                f.data.into_owned(),
            )
                .into_response(),
            None => (StatusCode::NOT_FOUND, "admin-ui not built").into_response(),
        },
    }
}
