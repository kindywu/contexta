use etl::{db, stardict};

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
