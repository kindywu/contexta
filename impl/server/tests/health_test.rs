use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use server::make_router;
use tower::ServiceExt;

#[tokio::test]
async fn health_returns_ok() {
    let app = make_router();
    let resp = app
        .oneshot(
            Request::builder()
                .uri("/api/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body = resp.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["code"], 0);
    assert_eq!(json["data"]["status"], "ok");
}
