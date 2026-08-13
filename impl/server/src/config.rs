use anyhow::Context;

#[derive(Debug, Clone)]
pub struct Config {
    pub port: u16,
    pub db_path: String,
    pub jwt_secret: String,
    pub deepseek_api_key: String,
    pub deepseek_base_url: String,
    pub deepseek_model: String,
    pub word_quota_daily: i64,
    pub article_budget_daily: i64,
    pub cache_ttl_days: i64,
    pub cache_max_rows: i64,
    pub daily_generate_hour: u8,
    pub admin_init_password: Option<String>,
    pub llm_timeout_secs: u64,
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        let cfg = Config {
            port: env_or("PORT", "8080")?.parse()?,
            db_path: env_or("DB_PATH", "contexta.db")?,
            jwt_secret: env_or("JWT_SECRET", "dev-secret-change-me")?,
            deepseek_api_key: std::env::var("DEEPSEEK_API_KEY")
                .context("DEEPSEEK_API_KEY must be set")?,
            deepseek_base_url: env_or("DEEPSEEK_BASE_URL", "https://api.deepseek.com")?,
            deepseek_model: env_or("DEEPSEEK_MODEL", "deepseek-v4-flash")?,
            word_quota_daily: env_or("WORD_QUOTA_DAILY", "200")?.parse()?,
            article_budget_daily: env_or("ARTICLE_BUDGET_DAILY", "100")?.parse()?,
            cache_ttl_days: env_or("CACHE_TTL_DAYS", "30")?.parse()?,
            cache_max_rows: env_or("CACHE_MAX_ROWS", "5000")?.parse()?,
            daily_generate_hour: env_or("DAILY_GENERATE_HOUR", "3")?.parse()?,
            admin_init_password: std::env::var("ADMIN_INIT_PASSWORD")
                .ok()
                .filter(|s| !s.is_empty()),
            llm_timeout_secs: env_or("LLM_TIMEOUT_SECS", "90")?.parse()?,
        };
        Ok(cfg)
    }
}

fn env_or(key: &str, default: &str) -> anyhow::Result<String> {
    Ok(std::env::var(key).unwrap_or_else(|_| default.to_string()))
}
