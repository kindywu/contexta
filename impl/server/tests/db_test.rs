use argon2::password_hash::PasswordVerifier;
use argon2::{Argon2, PasswordHash};
use server::db;
use std::sync::atomic::{AtomicU64, Ordering};

// T2 审查遗留：同进程并行测试共享 /tmp 路径会碰撞，用静态原子计数器给每个测试唯一后缀；
// 收尾 pool.close() 后删除主文件 + -wal/-shm 侧车文件（沿用 T3 加固模式）。
static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/contexta-dbtest-{}-{}.db", std::process::id(), n)
}

/// 收尾：close 连接池（等连接真正关闭，防 checkpoint 重建 -wal/-shm）→ 删主文件与侧车文件。
async fn cleanup(pool: sqlx::SqlitePool, db_path: &str) {
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

#[tokio::test]
async fn migrate_is_idempotent_and_creates_tables() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    // T2 审查遗留：账本断言——0→1 init 恰好 1 行
    let log_rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM schema_migration_log")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(log_rows, 1, "schema_migration_log 应恰好 1 行（0→1 init）");

    db::migrate(&pool).await.unwrap(); // 幂等：跑两次不报错
    let log_rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM schema_migration_log")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(
        log_rows, 1,
        "重复 migrate 不得追加账本行（幂等，链条起点不变）"
    );

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
        "prompt",
    ] {
        assert!(tables.contains(&t.to_string()), "missing table {t}");
    }
    // Task 2：prompt 种子——双 migrate 后仍 7 行（INSERT OR IGNORE 幂等，不重复插入）
    let seed_rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM prompt")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(seed_rows, 7, "prompt 种子应恰好 7 行，重复 migrate 不得重复插入");
    cleanup(pool, &path).await;
}

/// T2 审查遗留：seed_admin 单测——空表时插入、argon2 哈希可验证、重复 seed 不重复插入。
#[tokio::test]
async fn seed_admin_creates_verifiable_hash_and_is_idempotent() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    // 空表时插入
    db::seed_admin(&pool, "pw123").await.unwrap();
    let hash: String =
        sqlx::query_scalar("SELECT password_hash FROM admin_user WHERE username = 'admin'")
            .fetch_one(&pool)
            .await
            .unwrap();
    // argon2 哈希可验证：正确密码通过、错误密码拒绝
    let parsed = PasswordHash::new(&hash).unwrap();
    assert!(
        Argon2::default().verify_password(b"pw123", &parsed).is_ok(),
        "seed 的哈希应能验证初始密码"
    );
    assert!(
        Argon2::default()
            .verify_password(b"wrong", &parsed)
            .is_err(),
        "错误密码不得通过验证"
    );

    // 重复 seed 不重复插入，且不覆盖已有哈希
    db::seed_admin(&pool, "pw456").await.unwrap();
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM admin_user")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(count, 1, "重复 seed 不得重复插入");
    let hash2: String =
        sqlx::query_scalar("SELECT password_hash FROM admin_user WHERE username = 'admin'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert_eq!(hash, hash2, "重复 seed 不得覆盖已有哈希");

    cleanup(pool, &path).await;
}
