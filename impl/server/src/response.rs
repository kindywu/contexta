use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

#[derive(Serialize)]
pub struct ApiResult<T: Serialize> {
    pub code: i32,
    pub data: T,
}

#[derive(Serialize)]
pub struct ApiErrorBody {
    pub code: i32,
    pub message: String,
    pub error_code: &'static str,
}

pub enum AppError {
    BadRequest(&'static str, &'static str),
    QuotaExceeded(&'static str),
    Unauthorized(&'static str),
    Banned(&'static str),
    LlmFatal(&'static str),
    LlmRecoverableExhausted(&'static str),
    LlmTimeout(&'static str),
    PipelineBlocking(&'static str),
    Internal(anyhow::Error),
    NotFound(&'static str),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, code, error_code, message) = match self {
            AppError::BadRequest(ec, msg) => (StatusCode::BAD_REQUEST, 400, ec, msg),
            AppError::QuotaExceeded(m) => (StatusCode::BAD_REQUEST, 40001, "QUOTA_EXCEEDED", m),
            AppError::Unauthorized(ec) => (StatusCode::UNAUTHORIZED, 401, ec, "unauthorized"),
            AppError::Banned(m) => (StatusCode::FORBIDDEN, 403, "BANNED", m),
            AppError::LlmFatal(m) => (StatusCode::INTERNAL_SERVER_ERROR, 500, "LLM_FATAL", m),
            AppError::LlmRecoverableExhausted(m) => {
                (StatusCode::BAD_GATEWAY, 502, "LLM_RECOVERABLE_EXHAUSTED", m)
            }
            AppError::LlmTimeout(m) => (StatusCode::GATEWAY_TIMEOUT, 504, "LLM_TIMEOUT", m),
            AppError::PipelineBlocking(m) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                500,
                "PIPELINE_BLOCKING",
                m,
            ),
            AppError::Internal(e) => {
                tracing::error!("internal error: {e:?}");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    500,
                    "INTERNAL",
                    "internal error",
                )
            }
            AppError::NotFound(m) => (StatusCode::NOT_FOUND, 404, "NOT_FOUND", m),
        };
        (
            status,
            Json(ApiErrorBody {
                code,
                message: message.to_string(),
                error_code,
            }),
        )
            .into_response()
    }
}

impl From<anyhow::Error> for AppError {
    fn from(e: anyhow::Error) -> Self {
        AppError::Internal(e)
    }
}

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        AppError::Internal(anyhow::anyhow!(e))
    }
}

pub fn ok<T: Serialize>(data: T) -> Json<ApiResult<T>> {
    Json(ApiResult { code: 0, data })
}
