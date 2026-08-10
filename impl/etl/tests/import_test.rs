use std::fs;
use etl::cli::DumpArgs;

#[test]
fn import_roundtrip() {
    let root = etl::db::find_repo_root().expect("repo root");
    let src = root.join("impl/app/flutter/assets/contexta.db");
    let tmp = std::env::temp_dir().join(format!(
        "contexta_import_test_{}.db",
        std::process::id()
    ));
    fs::copy(&src, &tmp).expect("copy db");

    // 1. dump 两词到临时 jsonl（不污染 temp_docs）
    let jsonl = std::env::temp_dir().join("import_test_words.jsonl");
    let args = DumpArgs {
        all: false,
        words: Some(vec!["ephemeral".to_string(), "resilience".to_string()]),
        limit: None,
        max_samples: 10,
        output: Some(jsonl.clone()),
    };
    etl::dump::run_dump(&args).expect("dump");
    // 2. import 到临时库
    etl::importer::run_import(&jsonl, &tmp).expect("import");

    // 3. 验证：两词在库，且例句含词
    let conn = etl::db::open_ro(&tmp).expect("open");
    let n: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM word WHERE spelling_normalized IN ('ephemeral','resilience')",
            [],
            |r| r.get(0),
        )
        .expect("count");
    assert_eq!(n, 2);
    let ex: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM example_sentence e
             JOIN word_sense s ON s.id = e.word_sense_id
             JOIN word w ON w.id = s.word_id
             WHERE w.spelling_normalized = 'ephemeral'",
            [],
            |r| r.get(0),
        )
        .expect("ex count");
    assert!(ex >= 1);

    // 4. 原有数据未被删除（保守幂等）
    let before: i64 = conn
        .query_row("SELECT COUNT(*) FROM word", [], |r| r.get(0))
        .expect("total");
    assert!(before >= 17); // 15 原有 + 2 新增

    fs::remove_file(&tmp).ok();
    fs::remove_file(&jsonl).ok();
}
