//! Task 2：prompt 表种子 + prompt_service 单测（DB 读取 / 缺行 500 / 更新 / 未知 key）。
//! 隔离模式沿用既有：唯一库路径 + migrate + 收尾 close + 清理三件套。

use server::db;
use server::response::AppError;
use server::services::prompt_service::{
    PROMPT_KEYS, get_all_prompts, get_prompt, update_prompt,
};
use std::sync::atomic::{AtomicU64, Ordering};

static DB_SEQ: AtomicU64 = AtomicU64::new(0);

fn unique_db_path() -> String {
    let n = DB_SEQ.fetch_add(1, Ordering::Relaxed);
    format!("/tmp/ctx-prompt-{}-{}.db", std::process::id(), n)
}

async fn cleanup(pool: sqlx::SqlitePool, db_path: &str) {
    pool.close().await;
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db_path}{suffix}"));
    }
}

/// migrate 后：prompt 表恰好 7 行种子，key 集合与 PROMPT_KEYS 一致，
/// 内容非空（种子即默认内容，无第二副本），updated_at=0 标记种子。
#[tokio::test]
async fn migrate_seeds_seven_prompt_rows() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let rows: Vec<(String, String, i64)> =
        sqlx::query_as("SELECT key, content, updated_at FROM prompt ORDER BY key")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(rows.len(), 7, "应恰好 7 个 key 的种子");
    let mut keys: Vec<&str> = rows.iter().map(|(k, _, _)| k.as_str()).collect();
    keys.sort_unstable();
    let mut expected: Vec<&str> = PROMPT_KEYS.to_vec();
    expected.sort_unstable();
    assert_eq!(keys, expected, "种子 key 集合必须与 PROMPT_KEYS 一致");
    for (key, content, updated_at) in &rows {
        assert!(!content.trim().is_empty(), "种子 {key} 内容不得为空");
        assert_eq!(*updated_at, 0, "种子行 updated_at 必须为 0（种子标记）");
    }
    // 抽查一个 key 的真实内容落库（防空串种子）。
    let system: String = sqlx::query_scalar("SELECT content FROM prompt WHERE key = 'word_lookup_system'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert!(system.contains("You are an English-Chinese dictionary assistant."));
    cleanup(pool, &path).await;
}

/// get_prompt：返回 DB 当前行——覆盖种子后读到新值。
#[tokio::test]
async fn get_prompt_returns_updated_db_row() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    sqlx::query("UPDATE prompt SET content = 'CUSTOM DB CONTENT', updated_at = ? WHERE key = 'article_common'")
        .bind(1000i64)
        .execute(&pool)
        .await
        .unwrap();
    assert_eq!(
        get_prompt(&pool, "article_common").await.unwrap(),
        "CUSTOM DB CONTENT",
        "DB 行必须优先于嵌入默认"
    );
    cleanup(pool, &path).await;
}

/// get_prompt：缺行（种子被删）→ PipelineBlocking 500（数据完整性问题，无回退）。
#[tokio::test]
async fn get_prompt_missing_row_returns_pipeline_blocking() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    sqlx::query("DELETE FROM prompt WHERE key = 'word_lookup_system'")
        .execute(&pool)
        .await
        .unwrap();
    let err = get_prompt(&pool, "word_lookup_system").await.unwrap_err();
    assert!(
        matches!(err, AppError::PipelineBlocking(_)),
        "缺行必须 500 PipelineBlocking，实际: {err:?}"
    );
    cleanup(pool, &path).await;
}

/// 未知 key（表中无行）→ PipelineBlocking 500。
#[tokio::test]
async fn get_prompt_unknown_key_returns_pipeline_blocking() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let err = get_prompt(&pool, "nonexistent_key").await.unwrap_err();
    assert!(
        matches!(err, AppError::PipelineBlocking(_)),
        "未知 key 必须 500 PipelineBlocking，实际: {err:?}"
    );
    cleanup(pool, &path).await;
}

/// update_prompt：更新后 get_prompt 返回新值（trim 落库），updated_at 刷新（>0 种子标记）。
#[tokio::test]
async fn update_prompt_changes_content_and_updated_at() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    update_prompt(&pool, "article_high", "  NEW HIGH CONTENT  ")
        .await
        .unwrap();
    assert_eq!(
        get_prompt(&pool, "article_high").await.unwrap(),
        "NEW HIGH CONTENT",
        "更新后必须读到新内容（trim 落库）"
    );
    let updated_at: i64 =
        sqlx::query_scalar("SELECT updated_at FROM prompt WHERE key = 'article_high'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(updated_at > 0, "updated_at 必须刷新为当前时间，实际 {updated_at}");
    cleanup(pool, &path).await;
}

/// 未知 key 更新 → 400；内容不得被写入。
#[tokio::test]
async fn update_prompt_unknown_key_returns_bad_request() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let err = update_prompt(&pool, "nope", "x").await.unwrap_err();
    assert!(matches!(err, AppError::BadRequest(_, _)));
    let n: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM prompt WHERE key = 'nope'")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(n, 0, "未知 key 不得写入");
    cleanup(pool, &path).await;
}

/// 空内容更新 → 400；原内容不变。
#[tokio::test]
async fn update_prompt_empty_content_returns_bad_request() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let err = update_prompt(&pool, "article_common", "   ").await.unwrap_err();
    assert!(matches!(err, AppError::BadRequest(_, _)));
    let content: String =
        sqlx::query_scalar("SELECT content FROM prompt WHERE key = 'article_common'")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(
        !content.trim().is_empty(),
        "空内容更新不得改动种子原值"
    );
    cleanup(pool, &path).await;
}

/// get_all_prompts：7 行全量返回（key/content/updated_at 齐备）。
#[tokio::test]
async fn get_all_prompts_returns_all_seven_rows() {
    let path = unique_db_path();
    let pool = db::init_pool(&path).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let all = get_all_prompts(&pool).await.unwrap();
    assert_eq!(all.len(), 7);
    for p in all {
        assert!(!p.content.is_empty(), "key {} 内容不得为空", p.key);
        assert_eq!(p.updated_at, 0, "种子 updated_at 必须为 0");
        assert!(PROMPT_KEYS.contains(&p.key.as_str()), "未知 key: {}", p.key);
    }
    cleanup(pool, &path).await;
}
