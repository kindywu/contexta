use anyhow::Result;
use rusqlite::Connection;

use crate::align::word_regex;

pub struct WnSense {
    pub pos: String,
    pub definition: String,
}

const MAX_SENSES: usize = 8;

/// wn.db 英文词库（oewn）的 rowid。过滤中文词网（omw-cmn）必须依赖它——
/// omw-cmn 的 6.3 万中文词形是词集污染源（无释义，仅概念对齐）
const EN_LEXICON: &str = "(SELECT rowid FROM lexicons WHERE id LIKE 'oewn%')";

/// 词集枚举：流式游标，oewn 英文词库、排除含空格词形（专有名词/短语动词，阅读 UI 按词点选查不到）、
/// 排除含数字词形（数学/计量词网：115、10th、.22-caliber，非阅读单词）、
/// 按 form 排序去重（走 form_index）。每行回调一次 form（返回值被忽略，与 dump 的 process 统一签名）。
pub fn stream_forms(
    conn: &Connection,
    mut f: impl FnMut(&str) -> Result<bool>,
) -> Result<usize> {
    let mut stmt = conn.prepare(&format!(
        "SELECT DISTINCT form FROM forms
         WHERE lexicon_rowid = {EN_LEXICON}
           AND form NOT LIKE '% %' AND form NOT GLOB '*[0-9]*'
         ORDER BY form"
    ))?;
    let mut rows = stmt.query([])?;
    let mut n = 0usize;
    while let Some(row) = rows.next()? {
        let form: String = row.get(0)?;
        f(&form)?;
        n += 1;
    }
    Ok(n)
}

/// senses：JOIN 三表按 entry_rank 序；最多 8 条；definition 空串/'-' 跳过。
/// 限定英文词库——中文词网词形（理论上含少数英文形）不出义项
pub fn senses(conn: &Connection, word: &str) -> Result<Vec<WnSense>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT e.pos, d.definition
         FROM senses se
         JOIN forms f ON f.entry_rowid = se.entry_rowid
         JOIN entries e ON e.rowid = se.entry_rowid
         LEFT JOIN definitions d ON d.synset_rowid = se.synset_rowid
         WHERE f.form = ?1 AND f.lexicon_rowid = {EN_LEXICON}
         ORDER BY se.entry_rank, se.synset_rank"
    ))?;
    let mut rows = stmt.query([word])?;
    let mut out = Vec::new();
    while let Some(r) = rows.next()? {
        let pos: String = r.get(0)?;
        let def: Option<String> = r.get(1)?;
        let def = def.unwrap_or_default();
        if def.trim().is_empty() || def.trim() == "-" {
            continue;
        }
        out.push(WnSense { pos, definition: def });
        if out.len() >= MAX_SENSES {
            break;
        }
    }
    Ok(out)
}

/// 例句：synset_examples 挂 sense，含词过滤（预编译正则，逐条 is_match）
pub fn examples(conn: &Connection, word: &str) -> Result<Vec<String>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT DISTINCT ex.example FROM synset_examples ex
         JOIN senses se ON se.synset_rowid = ex.synset_rowid
         JOIN forms f ON f.entry_rowid = se.entry_rowid
         WHERE f.form = ?1 AND f.lexicon_rowid = {EN_LEXICON}
           AND ex.example IS NOT NULL AND ex.example != ''"
    ))?;
    let re = word_regex(word); // 预编译一次，全词例句复用
    let mut rows = stmt.query([word])?;
    let mut out = Vec::new();
    while let Some(r) = rows.next()? {
        let ex: String = r.get(0)?;
        if re.as_ref().is_some_and(|re| re.is_match(&ex)) {
            out.push(ex);
        }
    }
    Ok(out)
}

/// IPA：phonemic=1 优先，variety='en-US' 优先；无 → None
pub fn ipa(conn: &Connection, word: &str) -> Result<Option<String>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT value FROM pronunciations p
         JOIN forms f ON f.rowid = p.form_rowid
         WHERE f.form = ?1 AND f.lexicon_rowid = {EN_LEXICON} AND p.phonemic = 1
           AND p.value IS NOT NULL AND p.value != ''
         ORDER BY p.variety = 'en-US' DESC, p.rowid
         LIMIT 1"
    ))?;
    let mut rows = stmt.query([word])?;
    if let Some(r) = rows.next()? {
        return Ok(r.get(0)?);
    }
    Ok(None)
}
