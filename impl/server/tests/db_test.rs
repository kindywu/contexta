use server::db;

#[tokio::test]
async fn migrate_is_idempotent_and_creates_tables() {
    let path = format!("/tmp/contexta-test-{}.db", std::process::id());
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();
    db::migrate(&pool).await.unwrap(); // 幂等：跑两次不报错

    let tables: Vec<String> = sqlx::query_scalar(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    )
    .fetch_all(&pool)
    .await
    .unwrap();
    for t in [
        "users",
        "admin_user",
        "device_sessions",
        "article",
        "article_paragraph",
        "usage_log",
        "word_lookup_cache",
        "schema_migration_log",
    ] {
        assert!(tables.contains(&t.to_string()), "missing table {t}");
    }
    let _ = std::fs::remove_file(&path);
}
