use anyhow::Result;
use rusqlite::Connection;
use std::collections::HashMap;

pub struct LinguaRow {
    pub def_cn: String,
    pub example_en: String,
    pub example_cn: String,
}

/// 整表载入（30 词）：word → row
pub fn load_all(conn: &Connection) -> Result<HashMap<String, LinguaRow>> {
    let mut stmt = conn.prepare("SELECT word, def_cn, example_en, example_cn FROM words")?;
    let mut rows = stmt.query([])?;
    let mut map = HashMap::new();
    while let Some(r) = rows.next()? {
        let w: String = r.get(0)?;
        map.insert(
            w,
            LinguaRow {
                def_cn: r.get::<_, Option<String>>(1)?.unwrap_or_default(),
                example_en: r.get::<_, Option<String>>(2)?.unwrap_or_default(),
                example_cn: r.get::<_, Option<String>>(3)?.unwrap_or_default(),
            },
        );
    }
    Ok(map)
}
