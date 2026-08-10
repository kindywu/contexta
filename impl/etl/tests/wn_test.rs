use etl::{db, wn};

fn open() -> rusqlite::Connection {
    let root = db::find_repo_root().expect("repo root");
    db::open_ro(&root.join("impl/etl/ref/wn.db")).expect("wn.db")
}

#[test]
fn senses_ephemeral() {
    let conn = open();
    let s = wn::senses(&conn, "ephemeral").expect("senses");
    assert!(!s.is_empty());
    assert!(s
        .iter()
        .any(|x| x.definition.contains("lasting a very short time")));
}

#[test]
fn examples_ephemeral_contains_word() {
    let conn = open();
    let ex = wn::examples(&conn, "ephemeral").expect("examples");
    // 硬约束：每条例句必须含 ephemeral
    for e in &ex {
        assert!(e.to_lowercase().contains("ephemeral"));
    }
}

#[test]
fn ipa_ephemeral_some() {
    let conn = open();
    let ipa = wn::ipa(&conn, "ephemeral").expect("ipa");
    assert!(ipa.is_some());
    assert!(ipa.unwrap().contains('ə')); // IPA 字符
}
