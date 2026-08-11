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

#[test]
fn stream_forms_en_only_single_token() {
    let conn = open();
    let mut forms: Vec<String> = Vec::new();
    let n = wn::stream_forms(&conn, |f| {
        forms.push(f.to_string());
        Ok(true)
    })
    .expect("stream");

    // 词集规模：oewn 英文词库无空格无数字词形 ≈ 9 万（实测 89,899 − 数字 336）
    assert_eq!(n, forms.len());
    assert!((85_000..95_000).contains(&n));

    // 排序（stream 按 form 排序输出，保证可断点续跑与稳定 diff）
    assert!(forms.windows(2).all(|w| w[0] <= w[1]));

    // 硬约束 1：无含空格词形（短语/专有名词不进词集）
    assert!(forms.iter().all(|f| !f.contains(' ')));
    // 硬约束 2：无中文词形（omw-cmn 污染源，6.3 万条必须被 lexicon 过滤）
    assert!(forms.iter().all(|f| !f.chars().any(|c| c.is_alphabetic() && c as u32 > 0x2E80)));
    // 硬约束 3：无数字词形（数学/计量词网：115、10th，非阅读单词）
    assert!(forms.iter().all(|f| !f.chars().any(|c| c.is_ascii_digit())));
}

#[test]
fn stream_forms_contains_common_words() {
    let conn = open();
    let mut forms: Vec<String> = Vec::new();
    wn::stream_forms(&conn, |f| {
        forms.push(f.to_string());
        Ok(true)
    })
    .expect("stream");
    for w in ["dog", "run", "water", "ephemeral", "resilience"] {
        assert!(forms.iter().any(|f| f == w), "词集应包含 {w}");
    }
}
