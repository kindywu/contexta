use anyhow::Result;
use rusqlite::Connection;

pub struct StardictRow {
    pub word: String,
    pub phonetic: String,
    pub translation: String,
    pub pos: String,
}

const COLS: &str = "word, phonetic, translation, pos";

fn row_from(r: &rusqlite::Row) -> rusqlite::Result<StardictRow> {
    Ok(StardictRow {
        word: r.get(0)?,
        phonetic: r.get::<_, Option<String>>(1)?.unwrap_or_default(),
        translation: r.get::<_, Option<String>>(2)?.unwrap_or_default(),
        pos: r.get::<_, Option<String>>(3)?.unwrap_or_default(),
    })
}

/// 按词查（dump 中文增强用）。无 → None
pub fn lookup_word(conn: &Connection, word: &str) -> Result<Option<StardictRow>> {
    let mut stmt = conn.prepare(&format!("SELECT {COLS} FROM stardict WHERE word = ?1"))?;
    let mut rows = stmt.query_map([word], row_from)?;
    Ok(rows.next().transpose()?)
}
