use anyhow::{Context, Result};
use rusqlite::Connection;
use std::collections::HashSet;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

use crate::model::WordEntry;

pub fn run_import(file: &Path, target_db: &Path) -> Result<()> {
    let f = File::open(file).with_context(|| format!("无法打开 {}", file.display()))?;
    let reader = BufReader::new(f);
    let mut conn = Connection::open(target_db)
        .with_context(|| format!("无法打开目标库: {}", target_db.display()))?;

    // 已存在词集合（保守幂等：只跳过，不删除不覆盖）
    let mut existing = load_existing_words_conn(&conn)?;

    let mut imported = 0usize;
    let mut skipped = 0usize;
    let mut failed = 0usize;

    for (lineno, line) in reader.lines().enumerate() {
        let line = line.with_context(|| format!("第 {} 行读取失败", lineno + 1))?;
        let entry: WordEntry = match serde_json::from_str(&line) {
            Ok(e) => e,
            Err(e) => {
                eprintln!("⚠️ 第 {} 行 JSON 解析失败: {e}", lineno + 1);
                failed += 1;
                continue;
            }
        };
        if existing.contains(&entry.spelling_normalized) {
            skipped += 1;
            continue;
        }
        let tx = conn.transaction().with_context(|| "开启事务失败")?;
        let result = (|| -> Result<()> {
            tx.execute(
                "INSERT INTO word (spelling_normalized, spelling_display, phonetic_ipa)
                 VALUES (?1, ?2, ?3)",
                rusqlite::params![
                    entry.spelling_normalized,
                    entry.spelling_display,
                    entry.phonetic_ipa
                ],
            )?;
            let word_id = tx.last_insert_rowid();
            let mut sense_ids: Vec<i64> = Vec::with_capacity(entry.senses.len());
            for sense in &entry.senses {
                tx.execute(
                    "INSERT INTO word_sense
                     (word_id, order_index, part_of_speech, chinese_meaning, english_definition)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    rusqlite::params![
                        word_id,
                        sense.order_index,
                        sense.part_of_speech,
                        sense.chinese_meaning,
                        sense.english_definition
                    ],
                )?;
                sense_ids.push(tx.last_insert_rowid());
            }
            for ex in &entry.examples {
                let Some(&sense_id) = sense_ids.get(ex.sense_idx as usize) else {
                    continue; // sense_idx 越界，跳过该例句
                };
                tx.execute(
                    "INSERT INTO example_sentence
                     (word_sense_id, order_index, sentence_en, sentence_zh, is_primary)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    rusqlite::params![
                        sense_id,
                        ex.order_index,
                        ex.sentence_en,
                        ex.sentence_zh,
                        if ex.is_primary { 1 } else { 0 }
                    ],
                )?;
            }
            Ok(())
        })();
        match result {
            Ok(()) => {
                tx.commit()
                    .with_context(|| format!("{} 提交失败", entry.spelling_normalized))?;
                imported += 1;
                existing.insert(entry.spelling_normalized.clone()); // 同文件内重复行去重
            }
            Err(e) => {
                eprintln!("⚠️ [{}] 导入失败，回滚: {e}", entry.spelling_normalized);
                failed += 1;
            }
        }
    }

    println!("════ 结果 ════");
    println!(
        "  导入 {} 词，跳过已存在 {}，失败 {}",
        imported, skipped, failed
    );
    let total_words: i64 = conn.query_row("SELECT COUNT(*) FROM word", [], |r| r.get(0))?;
    println!("  目标库 word 总数: {total_words}");
    Ok(())
}

fn load_existing_words_conn(conn: &Connection) -> Result<HashSet<String>> {
    let mut stmt = conn.prepare("SELECT spelling_normalized FROM word")?;
    let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
    let mut set = HashSet::new();
    for row in rows {
        set.insert(row?);
    }
    Ok(set)
}
