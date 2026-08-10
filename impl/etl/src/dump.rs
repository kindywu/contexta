use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;

use crate::align::{allocate_examples, norm_pos, parse_cn_blocks};
use crate::cli::DumpArgs;
use crate::db::{find_repo_root, load_existing_words, open_ro};
use crate::model::{WordEntry, WordSense};
use crate::stardict::{lookup_word, stream_all, StardictRow};
use crate::wn;

pub const SAMPLE_WORDS: [&str; 3] = ["serendipity", "ephemeral", "resilience"];

/// 内部信号：--limit 到达，中断流式游标（不是错误）
#[derive(Debug)]
struct StopLimit;
impl std::fmt::Display for StopLimit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "limit 到达")
    }
}
impl std::error::Error for StopLimit {}

pub fn default_output() -> PathBuf {
    find_repo_root()
        .expect("repo root")
        .join("impl/etl/tmp/import_words.jsonl")
}

pub fn run_dump(args: &DumpArgs) -> Result<()> {
    let root = find_repo_root()?;
    let ref_dir = root.join("impl/etl/ref");
    for f in ["stardict.db", "wn.db"] {
        if !ref_dir.join(f).exists() {
            return Err(anyhow!("找不到词典库: {}", ref_dir.join(f).display()));
        }
    }
    let target_db = root.join("impl/app/flutter/assets/contexta.db");
    if !target_db.exists() {
        return Err(anyhow!("找不到目标库: {}", target_db.display()));
    }

    let stardict = open_ro(&ref_dir.join("stardict.db"))?;
    let wn_conn = open_ro(&ref_dir.join("wn.db"))?;
    let existing = load_existing_words(&target_db)?;

    let output = args.output.clone().unwrap_or_else(default_output);
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent).ok();
    }
    let file = File::create(&output)
        .map_err(|e| anyhow!("无法创建输出文件 {}: {e}", output.display()))?;
    let mut w = BufWriter::new(file);

    let mut total = 0usize;
    let mut skipped = 0usize;
    let mut written = 0usize;

    let mut process = |row: &StardictRow| -> Result<()> {
        total += 1;
        if args.all {
            if let Some(l) = args.limit {
                if total > l {
                    return Err(StopLimit.into());
                }
            }
        }
        if existing.contains(&row.word.to_lowercase()) {
            skipped += 1;
            return Ok(());
        }
        if let Some(entry) = build_entry(row, &wn_conn, args.max_samples)? {
            let line = serde_json::to_string(&entry)?;
            w.write_all(line.as_bytes())?;
            w.write_all(b"\n")?;
            written += 1;
        }
        if total % 10_000 == 0 {
            eprintln!("  进度: {total} 词");
        }
        Ok(())
    };

    match args.words.clone() {
        Some(words) => {
            if args.all {
                return Err(anyhow!("--all 与 --words 不能同时使用"));
            }
            for word in &words {
                let row = match lookup_word(&stardict, word)? {
                    Some(r) => r,
                    None => {
                        eprintln!("⚠️ stardict 无此词，跳过: {word}");
                        continue;
                    }
                };
                process(&row)?;
            }
        }
        None if args.all => {
            match stream_all(&stardict, &mut process) {
                Ok(_) => {}
                Err(e) if e.downcast_ref::<StopLimit>().is_some() => {} // 正常截断
                Err(e) => return Err(e),
            }
        }
        None => {
            // dump 无 --words 时默认与 sample 相同的精选词
            for word in SAMPLE_WORDS {
                let row = match lookup_word(&stardict, word)? {
                    Some(r) => r,
                    None => {
                        eprintln!("⚠️ stardict 无此词，跳过: {word}");
                        continue;
                    }
                };
                process(&row)?;
            }
        }
    }

    w.flush()?;
    drop(w);
    println!("✅ 已生成: {}", output.display());
    println!("   共 {} 词，跳过已存在 {}，写入 {}", total, skipped, written);
    preview(&output)?;
    Ok(())
}

fn build_entry(
    row: &StardictRow,
    wn_conn: &Connection,
    max_samples: usize,
) -> Result<Option<WordEntry>> {
    // 1. stardict：中文释义块（词性继承已内建）
    let cn_blocks = parse_cn_blocks(&row.translation);
    let sd_primary_pos = cn_blocks
        .first()
        .map(|(p, _)| p.clone())
        .unwrap_or_default();

    // 2. wn：senses + 例句 + IPA（例句含词过滤在 wn 层完成）
    let mut wn_senses = wn::senses(wn_conn, &row.word)?;
    if wn_senses.is_empty() {
        // 兜底：无 wn sense 时用 stardict pos 造 1 条空释义义项
        wn_senses.push(wn::WnSense {
            pos: if row.pos.is_empty() {
                sd_primary_pos.clone()
            } else {
                row.pos.clone()
            },
            definition: String::new(),
        });
    }
    let wn_examples = wn::examples(wn_conn, &row.word)?;
    let phonetic = wn::ipa(wn_conn, &row.word)?.or_else(|| {
        if row.phonetic.is_empty() {
            None
        } else {
            Some(row.phonetic.clone())
        }
    });

    // 3. 对齐：word_sense（bash 语义：pos_n = wn pos || 块词性；cn 按块 1:1 → 块 0 兜底 → 占位）
    let mut senses: Vec<WordSense> = Vec::new();
    for (i, s) in wn_senses.iter().enumerate() {
        let mut pos_n = if s.pos.is_empty() {
            sd_primary_pos.clone()
        } else {
            norm_pos(&s.pos)
        };
        let mut cn = String::new();
        if i < cn_blocks.len() {
            cn = cn_blocks[i].1.clone();
            if pos_n.is_empty() {
                pos_n = norm_pos(&cn_blocks[i].0);
            }
        } else if !cn_blocks.is_empty() {
            cn = cn_blocks[0].1.clone();
        }
        if cn.is_empty() && i == 0 {
            cn = "（无中文释义）".to_string();
        }
        senses.push(WordSense {
            order_index: i as i64,
            part_of_speech: if pos_n.is_empty() {
                sd_primary_pos.clone()
            } else {
                pos_n
            },
            chinese_meaning: cn,
            english_definition: s.definition.clone(),
        });
    }

    if senses.is_empty() {
        return Ok(None);
    }

    // 4. 例句分配：sense 0 优先（wn 无双语例句源，全走 wn 含词例句，sense 0 标 is_primary）
    let examples = allocate_examples(&senses, None, &wn_examples, max_samples);

    Ok(Some(WordEntry {
        spelling_normalized: row.word.to_lowercase(),
        spelling_display: row.word.clone(),
        phonetic_ipa: phonetic,
        senses,
        examples,
    }))
}

fn preview(path: &std::path::Path) -> Result<()> {
    use std::io::BufRead;
    let file = File::open(path)?;
    let reader = std::io::BufReader::new(file);
    println!("──────────────── 内容预览（前 40 行）────────────────");
    for line in reader.lines().take(40) {
        println!("{}", line?);
    }
    println!("──────────────────────────────────────────────");
    Ok(())
}
