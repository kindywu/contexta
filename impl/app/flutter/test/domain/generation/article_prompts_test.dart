import 'package:contexta/domain/generation/article_prompts.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-13（计划 B Task 6）：本地文章生成管道移除，buildArticleSystemPrompt /
/// buildArticleUserPrompt / parseArticleLlmResponse 及其测试删除，
/// 仅保留 categoryToDifficulty。
/// 2026-08-14（计划 B Task 7）：查词远程化，PromptLoader 与 prompts 夹具删除，
/// 其测试一并移除。
void main() {
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
}
