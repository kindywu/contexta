use crate::response::AppError;
use crate::services::prompt_service;
use sqlx::SqlitePool;

/// 查词 system prompt（DB 读取；内容在 prompt 表，缺行 → 500）。
pub async fn build_word_lookup_system(pool: &SqlitePool) -> Result<String, AppError> {
    prompt_service::get_prompt(pool, "word_lookup_system").await
}

/// 查词 user prompt：{{word}} 占位替换。
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

/// article system prompt：COMMON + <难度> 两节以 `\n\n` 拼接（DB 读取），
/// {{title}} 替换为 The Article Title。
pub async fn build_article_system(
    pool: &SqlitePool,
    difficulty: &str,
) -> Result<String, AppError> {
    let common = prompt_service::get_prompt(pool, "article_common").await?;
    let diff = prompt_service::get_prompt(pool, &format!("article_{}", difficulty.to_lowercase()))
        .await?;
    Ok(format!("{common}\n\n{diff}").replace("{{title}}", "The Article Title"))
}

/// article user prompt：占位替换（{{orderIndex}}/{{category}}）+ 分类指南追加。
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
