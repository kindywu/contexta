import '../model/word_detail.dart';
import 'prompt_loader.dart';

/// 查词 system prompt（对照 Kotlin WordPrompts.kt 的 buildWordLookupSystemPrompt）。
///
/// 加载 word_lookup_system.txt；文件缺失时用内置兜底字符串。
Future<String> buildWordLookupSystemPrompt() async => PromptLoader()
    .load('word_lookup_system.txt', _wordLookupSystemFallback);

/// 查词 user prompt（对照 Kotlin buildWordLookupUserPrompt）。
String buildWordLookupUserPrompt(String word) =>
    'Look up the word: $word\n\n'
    'Provide the spelling, phonetic transcription (if known), '
    'and all common senses with example sentences.';

/// 解析查词响应的 XML 格式：
/// `<spelling>` / `<phonetic>`? / `<sense>`（`<partOfSpeech>`/`<chineseMeaning>`/
/// `<englishDefinition>`/`<example>`（`<en>`/`<zh>`）?）*
///
/// 返回无 DB ID 的 WordDetail（wordId = 0，义项/例句 ID = 0）。
/// 无有效义项时返回 null（对照 Kotlin parseWordLlmResponse）。
WordDetail? parseWordLlmResponse(String content) {
  var spelling =
      RegExp(r'<spelling>([\s\S]*?)</spelling>').firstMatch(content)?.group(1)?.trim();
  if (spelling == null || spelling.isEmpty) {
    // 容错：LLM 偶发忽略格式，用查询词本身作根标签（如
    // <ocean>ocean</ocean>，真机日志 2026-08-10）——提取首个成对
    // 标签的内容兜底为拼写；仅接受单词/词组形态（无标签、无换行），
    // 拒绝把 <sense>/<phonetic> 等结构块当拼写。
    final candidate = RegExp(r'^<([A-Za-z][A-Za-z\-]*)>([\s\S]*?)</\1>')
        .firstMatch(content.trim())
        ?.group(2)
        ?.trim();
    if (candidate != null &&
        candidate.isNotEmpty &&
        RegExp(r"^[A-Za-z][A-Za-z'\-]*( [A-Za-z][A-Za-z'\-]*)?$")
            .hasMatch(candidate)) {
      spelling = candidate;
    }
  }
  if (spelling == null || spelling.isEmpty) return null; // 无任何拼写信息

  final phonetic =
      RegExp(r'<phonetic>([\s\S]*?)</phonetic>').firstMatch(content)?.group(1)?.trim();

  final senses = <WordSense>[];
  var senseIndex = 0;
  for (final senseMatch in RegExp(r'<sense>([\s\S]*?)</sense>')
      .allMatches(content)) {
    final senseContent = senseMatch.group(1)!;
    senseIndex++;

    final partOfSpeech = RegExp(r'<partOfSpeech>([\s\S]*?)</partOfSpeech>')
            .firstMatch(senseContent)
            ?.group(1)
            ?.trim() ??
        '';
    final chineseMeaning = RegExp(r'<chineseMeaning>([\s\S]*?)</chineseMeaning>')
            .firstMatch(senseContent)
            ?.group(1)
            ?.trim() ??
        '';
    final englishDefinition =
        RegExp(r'<englishDefinition>([\s\S]*?)</englishDefinition>')
                .firstMatch(senseContent)
                ?.group(1)
                ?.trim() ??
            '';

    final examples = <ExampleSentence>[];
    var exIndex = 0;
    for (final exMatch in RegExp(r'<example>([\s\S]*?)</example>')
        .allMatches(senseContent)) {
      final exContent = exMatch.group(1)!;
      exIndex++;
      examples.add(ExampleSentence(
        id: 0,
        orderIndex: exIndex,
        sentenceEn:
            RegExp(r'<en>([\s\S]*?)</en>').firstMatch(exContent)?.group(1)?.trim() ?? '',
        sentenceZh:
            RegExp(r'<zh>([\s\S]*?)</zh>').firstMatch(exContent)?.group(1)?.trim() ?? '',
        isPrimary: exIndex == 1,
      ));
    }

    senses.add(WordSense(
      id: 0,
      orderIndex: senseIndex,
      partOfSpeech: partOfSpeech,
      chineseMeaning: chineseMeaning,
      englishDefinition: englishDefinition,
      examples: examples,
    ));
  }

  if (senses.isEmpty) return null;

  return WordDetail(
    wordId: 0,
    spellingDisplay: spelling,
    phoneticIpa: phonetic,
    primarySense: senses.first,
    allSenses: senses,
    isInVocabulary: false,
    vocabularyEntryId: null,
  );
}

const _wordLookupSystemFallback = 'You are an English-Chinese dictionary '
    'assistant.\n'
    'Given an English word, provide its detailed definition for Chinese '
    'learners.\n'
    '\n'
    'Output format:\n'
    '<spelling>TheWord</spelling>\n'
    '<phonetic>/fəˈnɛtɪk/</phonetic>\n'
    '<sense>\n'
    '  <partOfSpeech>n.</partOfSpeech>\n'
    '  <chineseMeaning>中文释义</chineseMeaning>\n'
    '  <englishDefinition>English definition of this sense.</englishDefinition>\n'
    '  <example>\n'
    '    <en>Example sentence in English.</en>\n'
    '    <zh>例句的中文翻译。</zh>\n'
    '  </example>\n'
    '</sense>\n'
    '\n'
    'Rules:\n'
    '- <phonetic> is optional — include if available, omit the tag entirely '
    'if unknown\n'
    '- Provide 1-3 <sense> blocks; at least 1 is required\n'
    '- Each <sense> must have <partOfSpeech>, <chineseMeaning>, '
    '<englishDefinition>\n'
    '- Each <sense> should have 0-2 <example> blocks; <example> is optional\n'
    '- <example> must contain both <en> and <zh>\n'
    '- Output only the XML — no explanations, no markdown\n'
    '- Escape XML special characters: & → &amp;, < → &lt;, > → &gt;\n'
    '- The root element must be <spelling> — never wrap the word in a '
    'custom tag (e.g. <ocean>ocean</ocean>)';
