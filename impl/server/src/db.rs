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
/// 即 `&'static str`；001 来自 include_str!，零分配切片安全）。
/// 引号感知：SQL 字符串字面量内的 ';'（Task 2 prompt 种子内容含分号）不切分——
/// 单引号进入/离开字面量（'' 为转义的单引号，跳过不翻转）。'--' 注释（SQLite 语义：
/// 字符串外任意位置的 `--` 到行尾）内的 ';' 同样不切分；注释文本随语句保留由 SQLite 忽略。
fn split_statements(sql: &'static str) -> Vec<&'static str> {
    let mut out = Vec::new();
    let mut start = 0usize;
    let mut in_string = false;
    let b = sql.as_bytes();
    let mut i = 0usize;
    while i < b.len() {
        match b[i] {
            b'\'' if in_string && b.get(i + 1) == Some(&b'\'') => {
                i += 2; // '' 转义的单引号：内容的一部分，保持在字符串内
                continue;
            }
            b'\'' => in_string = !in_string,
            b'-' if !in_string && b.get(i + 1) == Some(&b'-') => {
                // 注释到行尾：跳过后 ';' 不会误切分
                while i < b.len() && b[i] != b'\n' {
                    i += 1;
                }
                continue;
            }
            b';' if !in_string => {
                let stmt = sql[start..i].trim();
                if !stmt.is_empty() {
                    out.push(stmt);
                }
                start = i + 1;
            }
            _ => {}
        }
        i += 1;
    }
    let last = sql[start..].trim();
    if !last.is_empty() {
        out.push(last);
    }
    out
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
