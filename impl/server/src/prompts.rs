use crate::response::AppError;
use crate::services::prompt_service;
use regex::Regex;
use sqlx::SqlitePool;
use std::collections::HashMap;

pub static WORD_LOOKUP_SYSTEM: &str = include_str!("prompts/word_lookup_system.txt");
pub static ARTICLE_SYSTEM: &str = include_str!("prompts/article_system.txt");

/// 移植 PromptLoader._sectionRegex + loadSection：提取命名节、替换 {{key}}。
///
/// Dart 正则为 `=== (\w+) ===\s*\n?(.*?)(?=\n=== |\Z)`（dotAll）；
/// 本仓库 regex crate 不支持 look-around，改用等价的两步实现：
/// （1）定位所有 `=== NAME ===` 节头；（2）节内容 = 节头到下一节头之间的文本（trim）。
/// 对编译期嵌入的固定模板，与 Dart 的 lookahead 边界语义等价（节头均独立成行）。
pub fn load_section(content: &str, sections: &[&str], params: &[(&str, &str)]) -> Option<String> {
    let header_re = Regex::new(r"=== (\w+) ===").unwrap();
    let headers: Vec<(usize, usize, String)> = header_re
        .captures_iter(content)
        .map(|c| {
            let m = c.get(0).unwrap();
            (m.start(), m.end(), c[1].to_string())
        })
        .collect();
    let mut map = HashMap::new();
    for (i, (_, end, name)) in headers.iter().enumerate() {
        let body_end = headers
            .get(i + 1)
            .map(|(s, _, _)| *s)
            .unwrap_or(content.len());
        map.insert(name.clone(), content[*end..body_end].trim().to_string());
    }
    let parts: Vec<String> = sections
        .iter()
        .filter_map(|s| map.get(*s).cloned())
        .collect();
    if parts.is_empty() {
        return None;
    }
    let mut result = parts.join("\n\n");
    for (k, v) in params {
        result = result.replace(&format!("{{{{{k}}}}}"), v);
    }
    Some(result)
}

/// 移植 buildWordLookupSystemPrompt：查词 system prompt（DB 优先，缺行回退嵌入默认）。
pub async fn build_word_lookup_system(pool: &SqlitePool) -> Result<String, AppError> {
    prompt_service::get_prompt(pool, "word_lookup_system").await
}

/// Task 2：查词 user prompt（原 llm_service 内联字符串 DB 化）：{{word}} 占位替换。
pub async fn build_word_lookup_user(pool: &SqlitePool, word: &str) -> Result<String, AppError> {
    Ok(prompt_service::get_prompt(pool, "word_lookup_user")
        .await?
        .replace("{{word}}", word))
}

/// 移植 categoryToDifficulty：内容分类 → 难度映射。
pub fn category_to_difficulty(category: &str) -> &'static str {
    match category {
        "DAILY_CONVERSATION" | "SCENE_DESCRIPTION" | "SIMPLE_STORY" => "LOW",
        "NEWS" | "EXPOSITORY" | "ARGUMENTATIVE" | "PERSONAL_ESSAY" => "MEDIUM",
        "ACADEMIC_EXCERPT"
        | "DEBATE_SPEECH"
        | "LEGAL_DOCUMENT"
        | "ART_CRITICISM"
        | "CLASSIC_NOVEL_EXCERPT" => "HIGH",
        _ => "MEDIUM",
    }
}

/// 移植 _categoryGuideline：分类 → 生成指南（全 12 分类；未知分类无指南）。
pub fn category_guideline(category: &str) -> Option<&'static str> {
    Some(match category {
        "DAILY_CONVERSATION" => "A natural everyday dialogue or scenario between two people.",
        "SCENE_DESCRIPTION" => "A vivid description of a place, event, or moment.",
        "SIMPLE_STORY" => "A short narrative with a clear beginning and end.",
        "NEWS" => "A brief news-style report on a current or hypothetical event.",
        "EXPOSITORY" => "An explanatory piece that teaches a concept.",
        "ARGUMENTATIVE" => "A short argument for or against a position.",
        "PERSONAL_ESSAY" => "A reflective first-person piece on an experience.",
        "ACADEMIC_EXCERPT" => "A scholarly excerpt suitable for advanced readers.",
        "DEBATE_SPEECH" => "A persuasive speech or debate opening statement.",
        "LEGAL_DOCUMENT" => "A simplified legal clause or contract excerpt.",
        "ART_CRITICISM" => "An analytical piece about an artwork or performance.",
        "CLASSIC_NOVEL_EXCERPT" => "An excerpt in the style of classic English literature.",
        _ => return None,
    })
}

/// 移植 buildArticleSystemPrompt：COMMON + <难度> 节以 `\n\n` 拼接（DB 读取，
/// 缺行回退嵌入默认），{{title}} 替换为 The Article Title（语义与嵌入版 load_section 等价）。
pub async fn build_article_system(
    pool: &SqlitePool,
    difficulty: &str,
) -> Result<String, AppError> {
    let common = prompt_service::get_prompt(pool, "article_common").await?;
    let diff = prompt_service::get_prompt(pool, &format!("article_{}", difficulty.to_lowercase()))
        .await?;
    Ok(format!("{common}\n\n{diff}").replace("{{title}}", "The Article Title"))
}

/// 移植 buildArticleUserPrompt：USER_PROMPT 节占位替换（{{orderIndex}}/{{category}}，
/// DB 读取，缺行回退嵌入默认）+ 分类指南追加。
pub async fn build_article_user(
    pool: &SqlitePool,
    category: &str,
    order_index: i64,
) -> Result<String, AppError> {
    let base = prompt_service::get_prompt(pool, "article_user_prompt")
        .await?
        .replace("{{orderIndex}}", &order_index.to_string())
        .replace("{{category}}", category);
    Ok(match category_guideline(category) {
        Some(g) => format!("{base}\n\nGuidelines for {category}:\n{g}"),
        None => base,
    })
}
