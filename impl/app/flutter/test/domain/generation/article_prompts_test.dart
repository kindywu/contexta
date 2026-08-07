import 'package:contexta/domain/generation/article_prompts.dart';
import 'package:contexta/domain/generation/prompt_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle 加载 asset 前必须先初始化 binding
  TestWidgetsFlutterBinding.ensureInitialized();

  group('categoryToDifficulty', () {
    test('LOW 分类', () {
      for (final c in ['DAILY_CONVERSATION', 'SCENE_DESCRIPTION', 'SIMPLE_STORY']) {
        expect(categoryToDifficulty(c), 'LOW', reason: c);
      }
    });

    test('MEDIUM 分类', () {
      for (final c in ['NEWS', 'EXPOSITORY', 'ARGUMENTATIVE', 'PERSONAL_ESSAY']) {
        expect(categoryToDifficulty(c), 'MEDIUM', reason: c);
      }
    });

    test('HIGH 分类', () {
      for (final c in [
        'ACADEMIC_EXCERPT',
        'DEBATE_SPEECH',
        'LEGAL_DOCUMENT',
        'ART_CRITICISM',
        'CLASSIC_NOVEL_EXCERPT',
      ]) {
        expect(categoryToDifficulty(c), 'HIGH', reason: c);
      }
    });

    test('未知分类回退 MEDIUM', () {
      expect(categoryToDifficulty('UNKNOWN_CATEGORY'), 'MEDIUM');
    });
  });

  group('buildArticleSystemPrompt', () {
    test('难度指定时包含 COMMON + 难度节', () async {
      final prompt = await buildArticleSystemPrompt('LOW');
      expect(prompt, contains('You are an English language learning content creator.'));
      expect(prompt, contains('Article length: total English word count must be 50-100 words.'));
      expect(prompt, contains('Output only the XML'));
    });

    test('MEDIUM 难度包含 100-300 词', () async {
      expect(await buildArticleSystemPrompt('MEDIUM'),
          contains('Article length: total English word count must be 100-300 words.'));
    });

    test('HIGH 难度包含 300-600 词', () async {
      expect(await buildArticleSystemPrompt('HIGH'),
          contains('Article length: total English word count must be 300-600 words.'));
    });

    test('难度为 null 时只含 COMMON', () async {
      final prompt = await buildArticleSystemPrompt();
      expect(prompt, contains('You are an English language learning content creator.'));
      expect(prompt, isNot(contains('Article length:')));
    });

    test('{{title}} 占位符被替换', () async {
      expect(await buildArticleSystemPrompt('LOW'), isNot(contains('{{title}}')));
      expect(await buildArticleSystemPrompt('LOW'), contains('The Article Title'));
    });
  });

  group('buildArticleUserPrompt', () {
    test('包含序号与分类', () async {
      final prompt = await buildArticleUserPrompt('NEWS', 3);
      expect(prompt, contains('Create article #3 in the category: NEWS'));
    });

    test('分类指南追加在基础提示后', () async {
      final prompt = await buildArticleUserPrompt('NEWS', 1);
      expect(prompt, contains('Guidelines for NEWS:'));
      expect(prompt, contains('A brief news-style report on a current or hypothetical event.'));
    });

    test('无指南的分类不追加（UNKNOWN）', () async {
      final prompt = await buildArticleUserPrompt('UNKNOWN_CATEGORY', 1);
      expect(prompt, isNot(contains('Guidelines')));
    });
  });

  group('parseArticleLlmResponse', () {
    test('标准响应解析出标题与段落', () {
      const content =
          '<title>My Title</title>'
          '<paragraph>Hello world</paragraph><translation>你好世界</translation>'
          '<paragraph>Second line.</paragraph><translation>第二行。</translation>';
      final (:title, :paragraphs) = parseArticleLlmResponse(content);
      expect(title, 'My Title');
      expect(paragraphs.length, 2);
      expect(paragraphs[0].orderIndex, 1);
      expect(paragraphs[0].englishText, 'Hello world');
      expect(paragraphs[0].chineseTranslation, '你好世界');
      expect(paragraphs[1].orderIndex, 2);
      expect(paragraphs[1].englishText, 'Second line.');
      expect(paragraphs[1].chineseTranslation, '第二行。');
    });

    test('无标题回退 Untitled', () {
      final (:title, :paragraphs) = parseArticleLlmResponse('<paragraph>x</paragraph>');
      expect(title, 'Untitled');
      expect(paragraphs.length, 1);
    });

    test('段落与翻译数量不匹配时翻译取空串', () {
      final (:title, :paragraphs) = parseArticleLlmResponse(
          '<paragraph>a</paragraph><paragraph>b</paragraph><translation>只有翻译</translation>');
      expect(paragraphs.length, 2);
      expect(paragraphs[0].chineseTranslation, '只有翻译');
      expect(paragraphs[1].chineseTranslation, '');
    });

    test('多行内容与空白规范化', () {
      const content = '<title>  T  </title>\n'
          ' <paragraph>  Hi  there.  </paragraph>\n'
          ' <translation>  你好。  </translation>';
      final (:title, :paragraphs) = parseArticleLlmResponse(content);
      expect(title, 'T');
      expect(paragraphs[0].englishText, 'Hi  there.');
      expect(paragraphs[0].chineseTranslation, '你好。');
    });
  });

  group('PromptLoader', () {
    test('loadSection 提取命名节并替换占位符', () async {
      // 用真实 asset 文件（flutter test 的 rootBundle 需要 TestWidgetsFlutterBinding）
      final loader = PromptLoader();
      final result = await loader.loadSection(
        'article_system.txt',
        ['COMMON', 'LOW'],
        params: {'title': 'X'},
        fallback: 'FALLBACK',
      );
      expect(result, isNot('FALLBACK'));
      expect(result, contains('Output only the XML'));
      expect(result, contains('50-100 words'));
      expect(result, isNot(contains('{{title}}')));
    });

    test('文件缺失回退 fallback', () async {
      final loader = PromptLoader();
      expect(await loader.load('no_such_file.txt', 'FALLBACK'), 'FALLBACK');
      expect(
        await loader.loadSection('no_such_file.txt', ['A'], fallback: 'FB'),
        'FB',
      );
    });

    test('节缺失回退 fallback', () async {
      final loader = PromptLoader();
      expect(
        await loader.loadSection('article_system.txt', ['NONEXISTENT'], fallback: 'FB'),
        'FB',
      );
    });
  });
}
