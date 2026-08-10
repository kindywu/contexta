/// 单词详情领域模型（对齐 Kotlin WordDetail.kt）。
class WordDetail {
  final int wordId;
  final String spellingDisplay;
  final String? phoneticIpa;
  final WordSense? primarySense;
  final List<WordSense> allSenses;
  final bool isInVocabulary;
  final int? vocabularyEntryId;

  const WordDetail({
    required this.wordId,
    required this.spellingDisplay,
    required this.phoneticIpa,
    required this.primarySense,
    required this.allSenses,
    this.isInVocabulary = false,
    this.vocabularyEntryId,
  });

  @override
  String toString() => 'WordDetail(wordId=$wordId, '
      'spellingDisplay=$spellingDisplay, phoneticIpa=$phoneticIpa, '
      'primarySense=$primarySense, allSenses=$allSenses, '
      'isInVocabulary=$isInVocabulary, vocabularyEntryId=$vocabularyEntryId)';
}

/// 单词义项（对齐 Kotlin WordSense）。
class WordSense {
  final int id;
  final int orderIndex;
  final String partOfSpeech;
  final String chineseMeaning;
  final String englishDefinition;
  final List<ExampleSentence> examples;

  const WordSense({
    required this.id,
    required this.orderIndex,
    required this.partOfSpeech,
    required this.chineseMeaning,
    required this.englishDefinition,
    required this.examples,
  });

  @override
  String toString() => 'WordSense(id=$id, orderIndex=$orderIndex, '
      'partOfSpeech=$partOfSpeech, chineseMeaning=$chineseMeaning, '
      'englishDefinition=$englishDefinition, examples=$examples)';
}

/// 例句（对齐 Kotlin ExampleSentence）。
class ExampleSentence {
  final int id;
  final int orderIndex;
  final String sentenceEn;
  final String sentenceZh;
  final bool isPrimary;

  const ExampleSentence({
    required this.id,
    required this.orderIndex,
    required this.sentenceEn,
    required this.sentenceZh,
    required this.isPrimary,
  });

  @override
  String toString() => 'ExampleSentence(id=$id, orderIndex=$orderIndex, '
      'sentenceEn=$sentenceEn, sentenceZh=$sentenceZh, isPrimary=$isPrimary)';
}
