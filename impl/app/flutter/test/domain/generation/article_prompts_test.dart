import 'package:contexta/domain/generation/article_prompts.dart';
import 'package:contexta/domain/generation/prompt_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-13（计划 B Task 6）：本地文章生成管道移除，buildArticleSystemPrompt /
/// buildArticleUserPrompt / parseArticleLlmResponse 及其测试删除，
/// 仅保留 categoryToDifficulty 与通用 PromptLoader 测试
/// （article_system.txt 保留作 loadSection 测试夹具）。
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
