use etl::{db, lingua, stardict};

fn open_ref(name: &str) -> rusqlite::Connection {
    let root = db::find_repo_root().expect("repo root");
    db::open_ro(&root.join(format!("impl/etl/ref/{name}.db"))).expect(name)
}

#[test]
fn lookup_serendipity_exists() {
    let conn = open_ref("stardict");
    let row = stardict::lookup_word(&conn, "serendipity")
        .expect("lookup")
        .expect("exists");
    assert_eq!(row.word, "serendipity");
    assert!(!row.translation.is_empty());
}

#[test]
fn lookup_missing_returns_none() {
    let conn = open_ref("stardict");
    assert!(stardict::lookup_word(&conn, "zzzznonexistentzzzz")
        .expect("lookup")
        .is_none());
}

#[test]
fn stream_all_counts_millions() {
    let conn = open_ref("stardict");
    let n = stardict::stream_all(&conn, |_| Ok(())).expect("stream");
    assert!(n > 3_000_000); // 340 万词
}

#[test]
fn lingua_load_all_has_30() {
    let conn = open_ref("lingua");
    let map = lingua::load_all(&conn).expect("load");
    assert_eq!(map.len(), 30);
}
