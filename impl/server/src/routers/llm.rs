use crate::AppState;
use crate::drivers::deepseek::DeepSeekClient;
use crate::extractors::AuthUser;
use crate::response::{ApiResult, AppError, ok};
use crate::services::llm_service;
use axum::Json;
use axum::extract::State;
use serde::Deserialize;

#[derive(Deserialize)]
pub struct WordLookupRequest {
    pub word: String,
}

pub async fn word_lookup(
    State(state): State<AppState>,
    auth: AuthUser,
    Json(req): Json<WordLookupRequest>,
) -> Result<Json<ApiResult<serde_json::Value>>, AppError> {
    let client = DeepSeekClient::new(&state.cfg)?;
    let result =
        llm_service::word_lookup(&state.pool, &state.cfg, &client, &auth.phone, &req.word).await?;
    Ok(ok(serde_json::to_value(result)?))
}
