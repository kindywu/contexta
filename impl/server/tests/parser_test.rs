//! Task 6: prompt 模板 + XML 解析器移植（对拍 Dart 用例）。
//!
//! 对拍源（Dart，只读）：
//! - impl/app/flutter/test/domain/generation/word_prompts_test.dart
//! - impl/app/flutter/test/domain/generation/article_prompts_test.dart
//!
//! 覆盖：parseWordLlmResponse（容错兜底/非法根标签/无义项/多义项顺序/例句
//! is_primary）、parseArticleLlmResponse（title 默认/翻译配对/空白规范化）、
//! categoryToDifficulty、_categoryGuideline、buildArticleSystemPrompt/
//! buildArticleUserPrompt、PromptLoader.loadSection。
//!
//! Task 2：build_* 构建函数 DB 化（签名 +pool，DB 行优先/缺行回退嵌入默认）——
//! 相关用例改为 tokio::test + 内存库（migrate 自带 7 行种子，走 DB 路径）；
//! load_section/category_guideline 等纯函数用例保持同步。

use server::llm::parser::{parse_article, parse_word_lookup};
use server::prompts::{
    ARTICLE_SYSTEM, build_article_system, build_article_user, build_word_lookup_system,
    build_word_lookup_user, category_guideline, category_to_difficulty, load_section,
};

/// Task 2：构建函数走 DB——内存库单连接池（max_connections=1 使 `sqlite::memory:`
/// 在池生命周期内保持同一库），migrate 后 prompt 表自带 7 行种子。
async fn prompt_db() -> sqlx::SqlitePool {
    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .unwrap();
    server::db::migrate(&pool).await.unwrap();
    pool
}

// ---------- parseWordLlmResponse（对拍 word_prompts_test.dart） ----------

#[test]
fn parses_full_word_lookup() {
    let xml = r#"<spelling>ocean</spelling><phonetic>/ˈoʊʃən/</phonetic>
<sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>海洋</chineseMeaning>
<englishDefinition>a large body of water</englishDefinition>
<example><en>The ocean is deep.</en><zh>海洋很深。</zh></example></sense>"#;
    let w = server::llm::parser::parse_word_lookup(xml).unwrap();
    assert_eq!(w.spelling, "ocean");
    assert_eq!(w.phonetic.as_deref(), Some("/ˈoʊʃən/"));
    assert_eq!(w.senses.len(), 1);
    assert_eq!(w.senses[0].examples.len(), 1);
    assert!(w.senses[0].examples[0].is_primary);
}

/// Dart「标准格式」用例补充断言：义项/例句字段提取。
#[test]
fn full_word_lookup_extracts_sense_fields() {
    // Dart 测试原文的 XML（带缩进与换行）
    let xml = r#"<spelling>ocean</spelling>
<phonetic>/ˈoʊʃən/</phonetic>
<sense>
  <partOfSpeech>n.</partOfSpeech>
  <chineseMeaning>海洋</chineseMeaning>
  <englishDefinition>A large body of salt water.</englishDefinition>
  <example>
    <en>The ocean is deep.</en>
    <zh>海洋很深。</zh>
  </example>
</sense>"#;
    let w = parse_word_lookup(xml).unwrap();
    assert_eq!(w.spelling, "ocean");
    assert_eq!(w.phonetic.as_deref(), Some("/ˈoʊʃən/"));
    assert_eq!(w.senses.len(), 1);
    let sense = &w.senses[0];
    assert_eq!(sense.order_index, 1);
    assert_eq!(sense.part_of_speech, "n.");
    assert_eq!(sense.chinese_meaning, "海洋");
    assert_eq!(sense.english_definition, "A large body of salt water.");
    assert_eq!(sense.examples.len(), 1);
    assert_eq!(sense.examples[0].sentence_en, "The ocean is deep.");
    assert_eq!(sense.examples[0].sentence_zh, "海洋很深。");
}

#[test]
fn spelling_missing_falls_back_to_root_tag() {
    // Dart: <ocean>ocean</ocean> 兜底（无 <spelling>）
    let xml = "<ocean>ocean</ocean><sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>x</chineseMeaning></sense>";
    let w = server::llm::parser::parse_word_lookup(xml).unwrap();
    assert_eq!(w.spelling, "ocean");
}

/// Dart「容错：LLM 用查询词作根标签」完整形态：兜底拼写 + 其余字段照常解析。
#[test]
fn root_tag_fallback_keeps_phonetic_and_senses() {
    let xml = r#"<ocean>ocean</ocean>
<phonetic>/ˈoʊʃən/</phonetic>
<sense>
  <partOfSpeech>n.</partOfSpeech>
  <chineseMeaning>海洋</chineseMeaning>
  <englishDefinition>A large body of salt water.</englishDefinition>
  <example>
    <en>The ocean is deep.</en>
    <zh>海洋很深。</zh>
  </example>
</sense>"#;
    let w = parse_word_lookup(xml).unwrap();
    assert_eq!(w.spelling, "ocean");
    assert_eq!(w.phonetic.as_deref(), Some("/ˈoʊʃən/"));
    assert_eq!(w.senses.len(), 1);
}

#[test]
fn invalid_root_tag_rejected() {
    // Dart: 根标签内容含结构块 → 拒绝
    let xml = "<sense><partOfSpeech>n.</partOfSpeech></sense>";
    assert!(server::llm::parser::parse_word_lookup(xml).is_none());
}

/// Dart「无任何拼写信息 → 返回 null」三个子场景。
#[test]
fn no_spelling_info_returns_none() {
    // 纯文本无任何标签
    assert!(parse_word_lookup("plain text no tags").is_none());
    // <spelling> 内容为空
    assert!(parse_word_lookup("<spelling></spelling>").is_none());
    // 结构块（<phonetic>/<sense>）不被兜底为拼写（非单词形态）
    assert!(
        parse_word_lookup(
            "<phonetic>/x/</phonetic>\n<sense>\n  <partOfSpeech>n.</partOfSpeech>\n</sense>"
        )
        .is_none()
    );
}

#[test]
fn no_senses_returns_none() {
    let xml = "<spelling>foo</spelling>";
    assert!(server::llm::parser::parse_word_lookup(xml).is_none());
}

/// 多义项 orderIndex 按出现顺序递增（Dart 无显式用例，逻辑在源码中，补测）。
#[test]
fn multi_sense_order_indices_increment() {
    let xml = r#"<spelling>run</spelling>
<sense><partOfSpeech>v.</partOfSpeech><chineseMeaning>跑</chineseMeaning></sense>
<sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>跑步</chineseMeaning></sense>"#;
    let w = parse_word_lookup(xml).unwrap();
    assert_eq!(w.senses.len(), 2);
    assert_eq!(w.senses[0].order_index, 1);
    assert_eq!(w.senses[0].part_of_speech, "v.");
    assert_eq!(w.senses[1].order_index, 2);
    assert_eq!(w.senses[1].part_of_speech, "n.");
}

/// 例句 is_primary 只在第一条（Dart 无显式用例，逻辑在源码中，补测）。
#[test]
fn example_is_primary_only_on_first() {
    let xml = r#"<spelling>ocean</spelling>
<sense><partOfSpeech>n.</partOfSpeech><chineseMeaning>海洋</chineseMeaning>
  <example><en>One.</en><zh>一。</zh></example>
  <example><en>Two.</en><zh>二。</zh></example></sense>"#;
    let w = parse_word_lookup(xml).unwrap();
    let examples = &w.senses[0].examples;
    assert_eq!(examples.len(), 2);
    assert_eq!(examples[0].order_index, 1);
    assert!(examples[0].is_primary);
    assert_eq!(examples[1].order_index, 2);
    assert!(!examples[1].is_primary);
}

// ---------- parseArticleLlmResponse（对拍 article_prompts_test.dart） ----------

#[test]
fn parses_article_with_translation_pairing() {
    let xml = "<title>Hello World</title><paragraph>One.</paragraph><translation>一。</translation><paragraph>Two.</paragraph>";
    let a = server::llm::parser::parse_article(xml);
    assert_eq!(a.title, "Hello World");
    assert_eq!(a.paragraphs.len(), 2);
    assert_eq!(a.paragraphs[0].2, "一。");
    assert_eq!(a.paragraphs[1].2, ""); // 翻译缺失 → 空串
}

#[test]
fn title_missing_defaults_untitled() {
    let xml = "<paragraph>Hi.</paragraph>";
    let a = server::llm::parser::parse_article(xml);
    assert_eq!(a.title, "Untitled");
}

/// Dart「标准响应」用例补充断言：orderIndex 从 1 递增。
#[test]
fn article_paragraph_order_indices_start_at_one() {
    let a = parse_article(
        "<paragraph>Hello world</paragraph><translation>你好世界</translation><paragraph>Second line.</paragraph><translation>第二行。</translation>",
    );
    assert_eq!(a.paragraphs.len(), 2);
    assert_eq!(a.paragraphs[0].0, 1);
    assert_eq!(a.paragraphs[0].1, "Hello world");
    assert_eq!(a.paragraphs[1].0, 2);
    assert_eq!(a.paragraphs[1].1, "Second line.");
}

/// Dart「段落与翻译数量不匹配时翻译取空串」。
#[test]
fn article_paragraph_translation_count_mismatch_leaves_empty() {
    let a = parse_article(
        "<paragraph>a</paragraph><paragraph>b</paragraph><translation>只有翻译</translation>",
    );
    assert_eq!(a.paragraphs.len(), 2);
    assert_eq!(a.paragraphs[0].2, "只有翻译");
    assert_eq!(a.paragraphs[1].2, "");
}

/// Dart「多行内容与空白规范化」：去首尾空白、保留内部空格。
#[test]
fn article_whitespace_normalization_trims_outer_whitespace() {
    let content = r#"<title>  T  </title>
 <paragraph>  Hi  there.  </paragraph>
 <translation>  你好。  </translation>"#;
    let a = parse_article(content);
    assert_eq!(a.title, "T");
    assert_eq!(a.paragraphs[0].1, "Hi  there.");
    assert_eq!(a.paragraphs[0].2, "你好。");
}

// ---------- categoryToDifficulty / _categoryGuideline ----------

#[test]
fn category_to_difficulty_maps_known_categories() {
    for c in ["DAILY_CONVERSATION", "SCENE_DESCRIPTION", "SIMPLE_STORY"] {
        assert_eq!(category_to_difficulty(c), "LOW", "category: {c}");
    }
    for c in ["NEWS", "EXPOSITORY", "ARGUMENTATIVE", "PERSONAL_ESSAY"] {
        assert_eq!(category_to_difficulty(c), "MEDIUM", "category: {c}");
    }
    for c in [
        "ACADEMIC_EXCERPT",
        "DEBATE_SPEECH",
        "LEGAL_DOCUMENT",
        "ART_CRITICISM",
        "CLASSIC_NOVEL_EXCERPT",
    ] {
        assert_eq!(category_to_difficulty(c), "HIGH", "category: {c}");
    }
}

#[test]
fn category_to_difficulty_unknown_falls_back_to_medium() {
    assert_eq!(category_to_difficulty("UNKNOWN_CATEGORY"), "MEDIUM");
}

#[test]
fn category_guideline_covers_all_known_categories() {
    let known = [
        "DAILY_CONVERSATION",
        "SCENE_DESCRIPTION",
        "SIMPLE_STORY",
        "NEWS",
        "EXPOSITORY",
        "ARGUMENTATIVE",
        "PERSONAL_ESSAY",
        "ACADEMIC_EXCERPT",
        "DEBATE_SPEECH",
        "LEGAL_DOCUMENT",
        "ART_CRITICISM",
        "CLASSIC_NOVEL_EXCERPT",
    ];
    for c in known {
        assert!(category_guideline(c).is_some(), "missing guideline for {c}");
    }
    assert!(category_guideline("UNKNOWN").is_none());
}

// ---------- buildArticleSystemPrompt / buildArticleUserPrompt ----------
// Task 2 起构建函数 DB 化（pool + migrate 种子），语义不变：common + 难度节 `\n\n`
// 连接、{{title}} 替换、USER_PROMPT 占位替换 + 分类指南追加。

#[tokio::test]
async fn build_article_system_low_combines_common_and_low() {
    let pool = prompt_db().await;
    let prompt = build_article_system(&pool, "LOW").await.unwrap();
    assert!(prompt.contains("You are an English language learning content creator."));
    assert!(prompt.contains("Article length: total English word count must be 50-100 words."));
    assert!(prompt.contains("Output only the XML"));
    pool.close().await;
}

#[tokio::test]
async fn build_article_system_medium_contains_100_300_words() {
    let pool = prompt_db().await;
    assert!(
        build_article_system(&pool, "MEDIUM")
            .await
            .unwrap()
            .contains("Article length: total English word count must be 100-300 words.")
    );
    pool.close().await;
}

#[tokio::test]
async fn build_article_system_high_contains_300_600_words() {
    let pool = prompt_db().await;
    assert!(
        build_article_system(&pool, "HIGH")
            .await
            .unwrap()
            .contains("Article length: total English word count must be 300-600 words.")
    );
    pool.close().await;
}

/// Dart「难度为 null 时只含 COMMON」：Rust 接口 difficulty 为 &str（无 null），
/// 等价路径 = 只请求 COMMON 节（load_section 直接调用）。
#[test]
fn build_article_system_common_only_without_difficulty_section() {
    let prompt = load_section(
        ARTICLE_SYSTEM,
        &["COMMON"],
        &[("title", "The Article Title")],
    )
    .unwrap();
    assert!(prompt.contains("You are an English language learning content creator."));
    assert!(!prompt.contains("Article length:"));
}

#[tokio::test]
async fn build_article_system_replaces_title_placeholder() {
    let pool = prompt_db().await;
    let prompt = build_article_system(&pool, "LOW").await.unwrap();
    assert!(!prompt.contains("{{title}}"));
    assert!(prompt.contains("The Article Title"));
    pool.close().await;
}

#[tokio::test]
async fn build_article_user_includes_order_index_and_category() {
    let pool = prompt_db().await;
    let prompt = build_article_user(&pool, "NEWS", 3).await.unwrap();
    assert!(prompt.contains("Create article #3 in the category: NEWS"));
    pool.close().await;
}

#[tokio::test]
async fn build_article_user_appends_category_guideline() {
    let pool = prompt_db().await;
    let prompt = build_article_user(&pool, "NEWS", 1).await.unwrap();
    assert!(prompt.contains("Guidelines for NEWS:"));
    assert!(prompt.contains("A brief news-style report on a current or hypothetical event."));
    pool.close().await;
}

#[tokio::test]
async fn build_article_user_unknown_category_omits_guideline() {
    let pool = prompt_db().await;
    let prompt = build_article_user(&pool, "UNKNOWN_CATEGORY", 1).await.unwrap();
    assert!(!prompt.contains("Guidelines"));
    pool.close().await;
}

/// Task 2：缺行回退嵌入默认——删光 prompt 种子后构建函数仍可用（运行时语义不因缺行变 500）。
#[tokio::test]
async fn build_functions_fall_back_to_embedded_defaults_without_seed_rows() {
    let pool = prompt_db().await;
    sqlx::query("DELETE FROM prompt").execute(&pool).await.unwrap();
    let system = build_article_system(&pool, "MEDIUM").await.unwrap();
    assert!(system.contains("100-300 words"));
    let user = build_article_user(&pool, "NEWS", 3).await.unwrap();
    assert!(user.contains("Create article #3 in the category: NEWS"));
    let wl = build_word_lookup_system(&pool).await.unwrap();
    assert!(wl.contains("You are an English-Chinese dictionary assistant."));
    let wl_user = build_word_lookup_user(&pool, "ocean").await.unwrap();
    assert!(wl_user.starts_with("Look up the word: ocean"));
    pool.close().await;
}

// ---------- PromptLoader.loadSection ----------

#[test]
fn load_section_extracts_sections_and_replaces_placeholders() {
    let result = load_section(ARTICLE_SYSTEM, &["COMMON", "LOW"], &[("title", "X")]).unwrap();
    assert!(result.contains("Output only the XML"));
    assert!(result.contains("50-100 words"));
    assert!(!result.contains("{{title}}"));
}

/// Dart「节缺失回退 fallback」：Rust 语义 = 返回 None。
/// （Dart「文件缺失回退」场景不适用：include_str! 编译期嵌入，文件不可能缺失。）
#[test]
fn load_section_returns_none_when_no_section_matches() {
    assert!(load_section(ARTICLE_SYSTEM, &["NONEXISTENT"], &[]).is_none());
}

// ---------- buildWordLookupSystemPrompt ----------

#[tokio::test]
async fn build_word_lookup_system_returns_embedded_template() {
    let pool = prompt_db().await;
    let s = build_word_lookup_system(&pool).await.unwrap();
    assert!(s.contains("You are an English-Chinese dictionary assistant."));
    assert!(s.contains("<spelling>TheWord</spelling>"));
    pool.close().await;
}

/// Task 2：word_lookup_user 占位替换——{{word}} 换成实际词，其余逐字不变。
#[tokio::test]
async fn build_word_lookup_user_replaces_word_placeholder() {
    let pool = prompt_db().await;
    let s = build_word_lookup_user(&pool, "ocean").await.unwrap();
    assert_eq!(
        s,
        "Look up the word: ocean\n\nProvide the spelling, phonetic transcription (if known), and all common senses with example sentences."
    );
    pool.close().await;
}
