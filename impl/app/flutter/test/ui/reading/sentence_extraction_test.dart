import 'package:contexta/ui/reading/sentence_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 阅读页句子切分（findSentenceRanges）测试：区间为 half-open (start, end)，
/// `text.substring(start, end)` 即得句子（含句末标点与收尾引号，不含空白）。
///
/// 切分准则偏保守——**漏切**只损失高亮粒度，**误切**会切断句子读音，
/// 故歧义处一律不切（缩写 / 小数 / 首字母 / 终止符后接小写）。

List<String> sentencesOf(String text) => splitSentences(text);

void main() {
  test('basic: splits at sentence-final punctuation', () {
    const text = 'The cat sat on the mat. The dog ran away! Did you see it?';
    expect(sentencesOf(text), const [
      'The cat sat on the mat.',
      'The dog ran away!',
      'Did you see it?',
    ]);
  });

  test('ranges are half-open and cover the punctuation', () {
    const text = 'Hello world. Bye.';
    expect(findSentenceRanges(text), const [(0, 12), (13, 17)]);
    expect(text.substring(0, 12), 'Hello world.');
    expect(text.substring(13, 17), 'Bye.');
  });

  test('trailing closing quote / bracket belongs to the sentence', () {
    const text = 'He said "Stop." Then he left.';
    expect(sentencesOf(text), const ['He said "Stop."', 'Then he left.']);

    const bracketed = 'It was late (about 9 p.m.) We went home.';
    expect(sentencesOf(bracketed), const ['It was late (about 9 p.m.)', 'We went home.']);
  });

  test('lowercase continuation is not a boundary (dialogue tag)', () {
    // "Stop!" she shouted. —— 感叹号在引号内，后接小写，属同一句
    const text = '"Stop!" she shouted.';
    expect(sentencesOf(text), const ['"Stop!" she shouted.']);
  });

  test('abbreviations do not end a sentence', () {
    const text = 'Mr. Smith met Dr. Jones at 5 p.m. yesterday. They talked.';
    expect(sentencesOf(text), const [
      'Mr. Smith met Dr. Jones at 5 p.m. yesterday.',
      'They talked.',
    ]);
  });

  test('initials do not end a sentence', () {
    const text = 'J. K. Rowling wrote the book. I read it.';
    expect(sentencesOf(text), const [
      'J. K. Rowling wrote the book.',
      'I read it.',
    ]);
  });

  test('decimal numbers are not split', () {
    const text = 'It costs 3.14 dollars. Cheap.';
    expect(sentencesOf(text), const ['It costs 3.14 dollars.', 'Cheap.']);
  });

  test('multi-part abbreviation merges conservatively (documented)', () {
    // 保守取向：U.S. 属缩写表 → 不切；漏切只影响高亮粒度，不影响朗读
    const text = 'He lives in the U.S. It is big.';
    expect(sentencesOf(text), const ['He lives in the U.S. It is big.']);
  });

  test('consecutive terminators form one boundary', () {
    const text = 'Wait... What?! Yes!';
    expect(sentencesOf(text), const ['Wait...', 'What?!', 'Yes!']);
  });

  test('text without final punctuation is one sentence', () {
    expect(sentencesOf('Hello world'), const ['Hello world']);
  });

  test('leading and trailing whitespace is excluded', () {
    const text = '  Hello there.   Bye now.  ';
    expect(findSentenceRanges(text), const [(2, 14), (17, 25)]);
    expect(sentencesOf(text), const ['Hello there.', 'Bye now.']);
  });

  test('newlines act as whitespace, not as boundaries', () {
    const text = 'Line one.\nLine two.';
    expect(sentencesOf(text), const ['Line one.', 'Line two.']);
  });

  test('empty and whitespace-only paragraphs yield no sentences', () {
    expect(sentencesOf(''), isEmpty);
    expect(sentencesOf('   \n  '), isEmpty);
  });

  test('ranges are ordered, non-overlapping, separated by whitespace only', () {
    const text = 'One.  Two! "Three?" Four';
    final ranges = findSentenceRanges(text);
    var cursor = 0;
    for (final (start, end) in ranges) {
      expect(start, greaterThanOrEqualTo(cursor));
      expect(text.substring(cursor, start).trim(), isEmpty);
      cursor = end;
    }
    expect(text.substring(cursor).trim(), isEmpty);
    expect(ranges.map((r) => text.substring(r.$1, r.$2)), [
      'One.',
      'Two!',
      '"Three?"',
      'Four',
    ]);
  });
}
