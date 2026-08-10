use anyhow::{anyhow, Context, Result};
use rusqlite::Connection;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// 从 CWD 逐级向上找含 ref/stardict.db 的目录；找不到 → Err
pub fn find_repo_root() -> Result<PathBuf> {
    let mut dir = std::env::current_dir().context("cannot read cwd")?;
    loop {
        if dir.join("ref/stardict.db").exists() {
            return Ok(dir);
        }
        if !dir.pop() {
            break;
        }
    }
    Err(anyhow!("找不到仓库根（未发现 ref/stardict.db，请从仓库内运行）"))
}

/// 打开只读 SQLite 连接（mode=ro）。路径不存在 → Err
pub fn open_ro(path: &Path) -> Result<Connection> {
    Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
        .with_context(|| format!("无法打开只读库: {}", path.display()))
}

/// 读目标库已存在词集合（SELECT spelling_normalized FROM word）
pub fn load_existing_words(target_db: &Path) -> Result<HashSet<String>> {
    let conn = open_ro(target_db)
        .with_context(|| format!("无法打开目标库: {}", target_db.display()))?;
    let mut stmt = conn.prepare("SELECT spelling_normalized FROM word")?;
    let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
    let mut set = HashSet::new();
    for row in rows {
        set.insert(row?);
    }
    Ok(set)
}
