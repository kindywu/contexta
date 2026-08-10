use etl::db;

#[test]
fn find_repo_root_from_cwd() {
    // 测试运行目录 = crate 根（或仓库根），向上找 impl/etl/ref/stardict.db 应命中仓库根
    let root = db::find_repo_root().expect("should find repo root");
    assert!(root.join("impl/etl/ref/stardict.db").exists());
}

#[test]
fn open_missing_errors() {
    assert!(db::open_ro(std::path::Path::new("/nonexistent/x.db")).is_err());
}
