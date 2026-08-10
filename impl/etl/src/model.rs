use serde::{Deserialize, Serialize};

/// 每行一个完整单词对象（JSONL）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WordEntry {
    pub spelling_normalized: String,
    pub spelling_display: String,
    pub phonetic_ipa: Option<String>,
    pub senses: Vec<WordSense>,
    pub examples: Vec<ExampleSentence>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WordSense {
    pub order_index: i64,
    pub part_of_speech: String,
    pub chinese_meaning: String,
    pub english_definition: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExampleSentence {
    /// 引用 senses[].order_index（import 时解析成 word_sense_id）
    pub sense_idx: i64,
    /// 义项内从 1 递增
    pub order_index: i64,
    pub sentence_en: String,
    pub sentence_zh: String,
    pub is_primary: bool,
}
