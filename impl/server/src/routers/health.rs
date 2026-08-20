use crate::response::{ApiResult, ok};
use axum::Json;
use serde::Serialize;

#[derive(Serialize)]
pub struct HealthData {
    pub status: &'static str,
}

pub async fn health() -> Json<ApiResult<HealthData>> {
    ok(HealthData { status: "ok" })
}
