use argon2::password_hash::{SaltString, rand_core::OsRng};
use argon2::{Argon2, PasswordHasher};
use chrono::Utc;
use sqlx::SqlitePool;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};

pub async fn init_pool(path: &str) -> anyhow::Result<SqlitePool> {
    let opts = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .foreign_keys(true);
    Ok(SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(opts)
        .await?)
}

pub async fn migrate(pool: &SqlitePool) -> anyhow::Result<()> {
    let sql = include_str!("../tool/migrations/001-init.sql");
    for stmt in split_statements(sql) {
        sqlx::query(stmt).execute(pool).await?;
    }
    let now = Utc::now().timestamp_millis();
    let exists: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM schema_migration_log WHERE to_version = 1")
            .fetch_one(pool)
            .await?;
    if exists == 0 {
        sqlx::query(
            "INSERT INTO schema_migration_log (from_version, to_version, description, created_at)
             VALUES (0, 1, 'init', ?)",
        )
        .bind(now)
        .execute(pool)
        .await?;
    }
    Ok(())
}

/// 按 ';' 切分，返回 `&'static str` 语句（sqlx 0.9 的 `query` 只接受 `SqlSafeStr`，
/// 即 `&'static str`；001 来自 include_str!，无内嵌分号，零分配切片安全）。
/// `--` 注释行随语句保留，由 SQLite 忽略（等效于原实现的跳过注释行）。
fn split_statements(sql: &'static str) -> Vec<&'static str> {
    sql.split(';')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect()
}

pub async fn seed_admin(pool: &SqlitePool, password: &str) -> anyhow::Result<()> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM admin_user")
        .fetch_one(pool)
        .await?;
    if count > 0 {
        return Ok(());
    }
    let salt = SaltString::generate(&mut OsRng);
    let hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!(e))?
        .to_string();
    let now = Utc::now().timestamp_millis();
    sqlx::query("INSERT INTO admin_user (username, password_hash, created_at, updated_at) VALUES ('admin', ?, ?, ?)")
        .bind(&hash).bind(now).bind(now).execute(pool).await?;
    tracing::info!("admin user 'admin' seeded");
    Ok(())
}
