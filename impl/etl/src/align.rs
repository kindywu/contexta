use regex::Regex;
use std::sync::OnceLock;

use crate::model::{ExampleSentence, WordSense};

/// 词性归一化：'a'/'j'→'adj.'、'n'→'n.'、'v'→'v.'；多缩写取前段；≤3 字母补 '.'
pub fn norm_pos(raw: &str) -> String {
    let first = raw
        .split('/')
        .next()
        .unwrap_or("")
        .split('.')
        .next()
        .unwrap_or("")
        .to_lowercase();
    match first.as_str() {
        "a" | "j" => "adj.".to_string(),
        "n" => "n.".to_string(),
        "v" => "v.".to_string(),
        s if !s.is_empty() && s.len() <= 3 => format!("{s}."),
        _ => first,
    }
}

/// 例句含词正则（\b + 忽略大小写），供 wn 查询层预编译复用；无词/含空格 → None
pub fn word_regex(word: &str) -> Option<Regex> {
    if word.is_empty() || word.contains(char::is_whitespace) {
        return None;
    }
    Regex::new(&format!(r"(?i)\b{}\b", regex::escape(word))).ok()
}

/// 例句是否包含目标词原形
pub fn example_contains_word(sentence: &str, word: &str) -> bool {
    word_regex(word).is_some_and(|re| re.is_match(sentence))
}

fn pos_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^([A-Za-z]+(?:[/.][A-Za-z]+)*)\.\s*(.*)$").unwrap())
}

fn badge_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"^\[[^\]]*\]\s*").unwrap())
}

/// stardict.translation 按行拆块 → 每块 (继承词性, 中文释义)（[医] 等标注块继承首块词性）
pub fn parse_cn_blocks(translation: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut inherited = String::new();
    for line in translation.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(cap) = pos_re().captures(line) {
            inherited = norm_pos(&cap[1]);
            out.push((inherited.clone(), cap[2].trim().to_string()));
        } else {
            let meaning = badge_re().replace(line, "");
            out.push((inherited.clone(), meaning.trim().to_string()));
        }
    }
    out
}

/// 从候选例句里挑出每词 ≤ max_samples 条：sense 0 优先 1 条中英对照（is_primary=true），
/// 其余义项按序各取 1 条 wn 例句（每义项至多 1 条）。返回 Vec<ExampleSentence>（sense_idx = order_index）
pub fn allocate_examples(
    senses: &[WordSense],
    lingua_pair: Option<(&str, &str)>, // (en, cn)，调用方已过含词过滤
    wn_examples: &[String],
    max_samples: usize,
) -> Vec<ExampleSentence> {
    if senses.is_empty() || max_samples == 0 {
        return Vec::new();
    }
    let mut out: Vec<ExampleSentence> = Vec::new();
    let mut wn_idx = 0usize;
    for sense in senses {
        if out.len() >= max_samples {
            break;
        }
        // sense 0 优先中英对照
        if sense.order_index == 0 {
            if let Some((en, cn)) = lingua_pair {
                out.push(ExampleSentence {
                    sense_idx: sense.order_index,
                    order_index: 1,
                    sentence_en: en.to_string(),
                    sentence_zh: cn.to_string(),
                    is_primary: true,
                });
                continue; // 义项 0 已有对照例句，不再取 wn
            }
        }
        // 其余义项（或义项 0 无对照时）各取 1 条 wn 例句
        if wn_idx < wn_examples.len() {
            out.push(ExampleSentence {
                sense_idx: sense.order_index,
                order_index: 1,
                sentence_en: wn_examples[wn_idx].clone(),
                sentence_zh: String::new(),
                is_primary: false,
            });
            wn_idx += 1;
        }
    }
    out
}
