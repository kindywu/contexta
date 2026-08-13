use regex::Regex;
use serde::{Deserialize, Serialize};

/// 移植 WordDetail 解析结果（无 DB ID 部分）。字段名即 App 端 JSON 契约。
#[derive(Serialize, Deserialize, Debug)]
pub struct ExampleOut {
    pub order_index: i64,
    pub sentence_en: String,
    pub sentence_zh: String,
    pub is_primary: bool,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct SenseOut {
    pub order_index: i64,
    pub part_of_speech: String,
    pub chinese_meaning: String,
    pub english_definition: String,
    pub examples: Vec<ExampleOut>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct WordLookup {
    pub spelling: String,
    pub phonetic: Option<String>,
    pub senses: Vec<SenseOut>,
}

/// 移植 Dart `RegExp(r'<tag>([\s\S]*?)</tag>').firstMatch()?.group(1)?.trim()`：
/// 非贪婪首配 + trim；`\s*` 包裹等价于 trim 效果。
fn first_match<'a>(content: &'a str, tag: &str) -> Option<&'a str> {
    let re = Regex::new(&format!(r"<{tag}>\s*([\s\S]*?)\s*</{tag}>")).unwrap();
    let caps = re.captures(content)?;
    Some(caps.get(1)?.as_str().trim())
}

/// 移植 parseWordLlmResponse（含容错兜底）。
///
/// 无 `<spelling>` 或内容为空时，用首个成对根标签的内容兜底为拼写
/// （如 `<ocean>ocean</ocean>`）；仅接受单词/词组形态（无标签、无换行），
/// 拒绝把 `<sense>`/`<phonetic>` 等结构块当拼写。regex crate 不支持反向引用
/// （Dart 的 `</\1>`），此处分两步实现：取开标签名 → 找最早的对应闭标签。
pub fn parse_word_lookup(content: &str) -> Option<WordLookup> {
    let mut spelling = first_match(content, "spelling").map(str::to_string);
    if spelling.is_none() || spelling.as_ref().is_some_and(|s| s.is_empty()) {
        // 容错：<ocean>ocean</ocean> 兜底（与 Dart 一致）
        let open_re = Regex::new(r"^<([A-Za-z][A-Za-z\-]*)>").unwrap();
        let trimmed = content.trim();
        if let Some(cap) = open_re.captures(trimmed) {
            let tag = &cap[1];
            let open_end = cap.get(0).unwrap().end();
            let close = format!("</{tag}>");
            if let Some(close_start) = trimmed[open_end..].find(&close).map(|i| i + open_end) {
                let candidate = trimmed[open_end..close_start].trim();
                let valid = Regex::new(r"^[A-Za-z][A-Za-z'\-]*( [A-Za-z][A-Za-z'\-]*)?$").unwrap();
                if valid.is_match(candidate) {
                    spelling = Some(candidate.to_string());
                }
            }
        }
    }
    let spelling = spelling?;
    if spelling.is_empty() {
        return None;
    }

    let phonetic = first_match(content, "phonetic").map(str::to_string);

    let sense_re = Regex::new(r"<sense>([\s\S]*?)</sense>").unwrap();
    // 例句正则在义项循环外编译一次（同模式每轮复用）
    let ex_re = Regex::new(r"<example>([\s\S]*?)</example>").unwrap();
    let mut senses = Vec::new();
    for (idx, cap) in sense_re.captures_iter(content).enumerate() {
        let sc = cap[1].to_string();
        let sense_index = idx as i64 + 1;
        let part_of_speech = first_match(&sc, "partOfSpeech").unwrap_or("").to_string();
        let chinese_meaning = first_match(&sc, "chineseMeaning").unwrap_or("").to_string();
        let english_definition = first_match(&sc, "englishDefinition")
            .unwrap_or("")
            .to_string();
        let mut examples = Vec::new();
        for (ex_idx, excap) in ex_re.captures_iter(&sc).enumerate() {
            let ec = excap[1].to_string();
            let ex_index = ex_idx as i64 + 1;
            examples.push(ExampleOut {
                order_index: ex_index,
                sentence_en: first_match(&ec, "en").unwrap_or("").to_string(),
                sentence_zh: first_match(&ec, "zh").unwrap_or("").to_string(),
                is_primary: ex_index == 1,
            });
        }
        senses.push(SenseOut {
            order_index: sense_index,
            part_of_speech,
            chinese_meaning,
            english_definition,
            examples,
        });
    }
    if senses.is_empty() {
        return None;
    }
    Some(WordLookup {
        spelling,
        phonetic,
        senses,
    })
}

/// 移植 parseArticleLlmResponse：`<title>` 缺失默认 "Untitled"；
/// 段落与翻译按顺序配对，翻译缺失取空串。
pub struct ArticleDraft {
    pub title: String,
    pub paragraphs: Vec<(i64, String, String)>,
}

pub fn parse_article(content: &str) -> ArticleDraft {
    let title = first_match(content, "title")
        .unwrap_or("Untitled")
        .to_string();
    let para_re = Regex::new(r"<paragraph>([\s\S]*?)</paragraph>").unwrap();
    let trans_re = Regex::new(r"<translation>([\s\S]*?)</translation>").unwrap();
    let paragraphs: Vec<String> = para_re
        .captures_iter(content)
        .map(|c| c[1].trim().to_string())
        .collect();
    let translations: Vec<String> = trans_re
        .captures_iter(content)
        .map(|c| c[1].trim().to_string())
        .collect();
    let body = paragraphs
        .iter()
        .enumerate()
        .map(|(i, p)| {
            (
                i as i64 + 1,
                p.clone(),
                translations.get(i).cloned().unwrap_or_default(),
            )
        })
        .collect();
    ArticleDraft {
        title,
        paragraphs: body,
    }
}
