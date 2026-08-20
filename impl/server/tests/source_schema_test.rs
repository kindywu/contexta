//! 迁移结构契约测试：article_source 表（10 列）、article.source_article_id 列、
//! article_user_prompt 种子含新占位符、表可写入（body 列）。
use chrono::Utc;
use server::db;
use sqlx::SqlitePool;
use std::sync::atomic::{AtomicUsize, Ordering};

static DB_SEQ: AtomicUsize = AtomicUsize::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-src-schema-{}-{}.db", std::process::id(), n)
}

async fn cleanup(pool: SqlitePool, db_path: &str) {
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

#[tokio::test]
async fn migration_creates_source_schema_and_prompt_seed() {
    let db_path = unique_db_path();
    let pool = db::init_pool(&db_path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    // article_source 列定义（declaration order）与 001-init.sql 一致
    let cols: Vec<String> = sqlx::query_scalar(
        "SELECT name FROM pragma_table_info('article_source') ORDER BY cid",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(
        cols,
        vec![
            "id", "source_url", "title", "body", "published_at", "is_used",
            "created_at", "updated_at", "is_deleted", "deleted_at"
        ],
        "article_source 列定义与 001-init.sql 一致"
    );
    // article 有 source_article_id 列
    let col: Option<String> = sqlx::query_scalar(
        "SELECT name FROM pragma_table_info('article') WHERE name = 'source_article_id'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(col.as_deref(), Some("source_article_id"));
    // 种子含新占位符（对新库 INSERT OR IGNORE 生效）
    let content: String = sqlx::query_scalar(
        "SELECT content FROM prompt WHERE key = 'article_user_prompt'",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(content.contains("{{sourceArticle}}"), "种子须含 {{sourceArticle}} 占位符");
    assert!(content.contains("{{recentTitles}}"), "种子须含 {{recentTitles}} 占位符");
    // body 列可写入
    let now = Utc::now().timestamp_millis();
    sqlx::query(
        "INSERT INTO article_source (source_url, title, body, published_at, is_used, created_at, updated_at)
         VALUES ('https://cd.example/a1', 't', 'b', '2026-08-17', 0, ?, ?)",
    )
    .bind(now)
    .bind(now)
    .execute(&pool)
    .await
    .unwrap();
    cleanup(pool, &db_path).await;
}
