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
    pub chinadaily_base_url: String,      // CHINADAILY_BASE_URL（事实源抓取基址）
    pub source_max_age_days: i64,         // SOURCE_MAX_AGE_DAYS（只选近 N 天来源，保证新鲜）
    pub source_fetch_timeout_secs: u64,   // SOURCE_FETCH_TIMEOUT_SECS（单请求兜底超时）
    pub recent_title_days: i64,           // RECENT_TITLE_DAYS（标题防重注入窗口）
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        let cfg = Config {
            port: env_or("PORT", "8080")?.parse()?,
            db_path: env_or("DB_PATH", "contexta.db")?,
            // I3（审查）：JWT_SECRET 最小长度校验（HS256 安全下限）。测试直接构造 Config，不经 load，不受影响。
            jwt_secret: {
                let s = std::env::var("JWT_SECRET").context("JWT_SECRET must be set")?;
                if s.len() < 32 {
                    return Err(anyhow::anyhow!(
                        "JWT_SECRET must be at least 32 characters, got {}",
                        s.len()
                    ));
                }
                s
            },
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
            chinadaily_base_url: env_or("CHINADAILY_BASE_URL", "https://www.chinadaily.com.cn")?,
            source_max_age_days: env_or("SOURCE_MAX_AGE_DAYS", "3")?.parse()?,
            source_fetch_timeout_secs: env_or("SOURCE_FETCH_TIMEOUT_SECS", "15")?.parse()?,
            recent_title_days: env_or("RECENT_TITLE_DAYS", "14")?.parse()?,
        };
        Ok(cfg)
    }
}

fn env_or(key: &str, default: &str) -> anyhow::Result<String> {
    Ok(std::env::var(key).unwrap_or_else(|_| default.to_string()))
}
