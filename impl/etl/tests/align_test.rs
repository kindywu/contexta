use etl::align::{allocate_examples, example_contains_word, norm_pos, parse_cn_blocks};
use etl::model::WordSense;

#[test]
fn norm_pos_short() {
    assert_eq!(norm_pos("n"), "n.");
    assert_eq!(norm_pos("a"), "adj.");
    assert_eq!(norm_pos("j"), "adj.");
    assert_eq!(norm_pos("v"), "v.");
    assert_eq!(norm_pos("vt./vi."), "vt.");
    assert_eq!(norm_pos("adjective"), "adjective"); // 长词不加点
}

#[test]
fn parse_cn_blocks_inherits_pos() {
    let blocks = parse_cn_blocks("n. 苹果\n[医] 香蕉\nvt. 吃");
    assert_eq!(blocks.len(), 3);
    assert_eq!(blocks[0], ("n.".to_string(), "苹果".to_string()));
    assert_eq!(blocks[1], ("n.".to_string(), "香蕉".to_string())); // [医] 继承首块词性
    assert_eq!(blocks[2], ("vt.".to_string(), "吃".to_string()));
}

#[test]
fn example_contains_word_matches() {
    assert!(example_contains_word("the ephemeral joys of childhood", "ephemeral"));
    assert!(!example_contains_word("a passing fancy", "ephemeral")); // 不含原形
    assert!(example_contains_word("Ephemeral things pass.", "ephemeral")); // 忽略大小写
    assert!(!example_contains_word("the ephemerals", "ephemeral")); // 词边界 \b
}

#[test]
fn allocate_examples_primary_first_and_cap() {
    let senses = vec![
        WordSense { order_index: 0, part_of_speech: "n.".into(), chinese_meaning: "".into(), english_definition: "".into() },
        WordSense { order_index: 1, part_of_speech: "n.".into(), chinese_meaning: "".into(), english_definition: "".into() },
        WordSense { order_index: 2, part_of_speech: "n.".into(), chinese_meaning: "".into(), english_definition: "".into() },
    ];
    let lingua = Some(("Building resilience is key.", "建立韧性是关键。"));
    let wn = vec!["a wn example one".to_string(), "a wn example two".to_string()];
    let ex = allocate_examples(&senses, lingua, &wn, 10);
    assert_eq!(ex.len(), 3);
    assert_eq!(ex[0].sense_idx, 0);
    assert!(ex[0].is_primary);
    assert_eq!(ex[0].sentence_zh, "建立韧性是关键。");
    assert_eq!(ex[1].sense_idx, 1);
    assert_eq!(ex[2].sense_idx, 2);
    assert_eq!(ex[1].order_index, 1);
}

#[test]
fn allocate_examples_respects_max() {
    let senses = (0..5)
        .map(|i| WordSense { order_index: i, part_of_speech: "n.".into(), chinese_meaning: "".into(), english_definition: "".into() })
        .collect::<Vec<_>>();
    let wn = vec!["ex one".to_string(), "ex two".to_string(), "ex three".to_string()];
    let ex = allocate_examples(&senses, None, &wn, 2);
    assert_eq!(ex.len(), 2); // 上限 2 条
}
