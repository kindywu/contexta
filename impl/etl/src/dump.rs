use anyhow::{anyhow, Result};
use rusqlite::Connection;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;

use crate::align::{allocate_examples, norm_pos, parse_cn_blocks};
use crate::cli::DumpArgs;
use crate::db::{find_repo_root, load_existing_words, open_ro};
use crate::model::{WordEntry, WordSense};
use crate::stardict::{lookup_word, StardictRow};
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
    let mut no_sense = 0usize;

    // 词集驱动（wn 主源）：每词回调；--all 流式枚举 wn forms，--words/sample 逐个查 wn
    let mut process = |word: &str| -> Result<bool> {
        total += 1;
        if args.all {
            if let Some(l) = args.limit {
                if total > l {
                    return Err(StopLimit.into());
                }
            }
        }
        if existing.contains(&word.to_lowercase()) {
            skipped += 1;
            return Ok(false);
        }
        // stardict 仅作中文增强（查不到 → None，中文走「（无中文释义）」占位）
        let sd = lookup_word(&stardict, word)?;
        match build_entry(word, sd.as_ref(), &wn_conn, args.max_samples)? {
            Some(entry) => {
                let line = serde_json::to_string(&entry)?;
                w.write_all(line.as_bytes())?;
                w.write_all(b"\n")?;
                written += 1;
                Ok(true)
            }
            None => {
                no_sense += 1;
                Ok(false)
            }
        }
    };

    match args.words.clone() {
        Some(words) => {
            if args.all {
                return Err(anyhow!("--all 与 --words 不能同时使用"));
            }
            for word in &words {
                if !process(&word)? {
                    eprintln!("⚠️ wn 无义项，跳过: {word}");
                }
            }
        }
        None if args.all => {
            match wn::stream_forms(&wn_conn, &mut process) {
                Ok(_) => {}
                Err(e) if e.downcast_ref::<StopLimit>().is_some() => {} // 正常截断
                Err(e) => return Err(e),
            }
        }
        None => {
            // dump 无 --words 时默认与 sample 相同的精选词
            for word in SAMPLE_WORDS {
                if !process(word)? {
                    eprintln!("⚠️ wn 无义项，跳过: {word}");
                }
            }
        }
    }

    w.flush()?;
    drop(w);
    println!("✅ 已生成: {}", output.display());
    println!(
        "   共 {} 词，跳过已存在 {}，wn 无义项 {}，写入 {}",
        total, skipped, no_sense, written
    );
    preview(&output)?;
    Ok(())
}

/// 词条构建：wn 是义项事实主，stardict 仅补中文/词性/音标。
/// word 在 wn 无义项 → None（跳过，不造空义项；app 运行时 LLM 兜底）
fn build_entry(
    word: &str,
    sd: Option<&StardictRow>,
    wn_conn: &Connection,
    max_samples: usize,
) -> Result<Option<WordEntry>> {
    // 1. wn：senses + 例句 + IPA（例句含词过滤在 wn 层完成）——词集 100% 来自 wn
    let wn_senses = wn::senses(wn_conn, word)?;
    if wn_senses.is_empty() {
        return Ok(None);
    }
    let wn_examples = wn::examples(wn_conn, word)?;
    let phonetic = wn::ipa(wn_conn, word)?.or_else(|| {
        let p = sd.map(|r| r.phonetic.as_str()).unwrap_or("");
        if p.is_empty() {
            None
        } else {
            Some(p.to_string())
        }
    });

    // 2. stardict：中文释义块（词性继承已内建）；无 → 全空，走「（无中文释义）」占位
    let (cn_blocks, sd_primary_pos) = match sd {
        Some(row) => {
            let blocks = parse_cn_blocks(&row.translation);
            let primary = blocks.first().map(|(p, _)| p.clone()).unwrap_or_default();
            (blocks, primary)
        }
        None => (Vec::new(), String::new()),
    };

    // 3. 对齐：word_sense（pos_n = wn pos || 块词性；cn 按块 1:1 → 块 0 兜底 → 占位）
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

    // 4. 例句分配：sense 0 优先（wn 无双语例句源，全走 wn 含词例句，sense 0 标 is_primary）
    let examples = allocate_examples(&senses, None, &wn_examples, max_samples);

    Ok(Some(WordEntry {
        spelling_normalized: word.to_lowercase(),
        spelling_display: word.to_string(),
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
