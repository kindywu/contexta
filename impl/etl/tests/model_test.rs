use etl::model::{ExampleSentence, WordEntry, WordSense};

#[test]
fn json_roundtrip() {
    let entry = WordEntry {
        spelling_normalized: "ephemeral".into(),
        spelling_display: "ephemeral".into(),
        phonetic_ipa: Some("ɛˈfɛ.mə.ɹəl".into()),
        senses: vec![WordSense {
            order_index: 0,
            part_of_speech: "adj.".into(),
            chinese_meaning: "朝生暮死的".into(),
            english_definition: "lasting a very short time".into(),
        }],
        examples: vec![ExampleSentence {
            sense_idx: 0,
            order_index: 1,
            sentence_en: "the ephemeral joys of childhood".into(),
            sentence_zh: String::new(),
            is_primary: true,
        }],
    };
    let json = serde_json::to_string(&entry).unwrap();
    let back: WordEntry = serde_json::from_str(&json).unwrap();
    assert_eq!(back.spelling_normalized, "ephemeral");
    assert_eq!(back.senses.len(), 1);
    assert_eq!(back.senses[0].part_of_speech, "adj.");
    assert!(back.examples[0].is_primary);
    // 无 examples 时序列化需自洽（空数组）
    let empty = WordEntry {
        examples: vec![],
        ..entry
    };
    let json2 = serde_json::to_string(&empty).unwrap();
    assert!(json2.contains("\"examples\":[]"));
}
