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

    /// 2026-10-07 回归：服务端同步落地的是**小写 snake_case**（`engine/schema.ts`
    /// 的 Category 枚举），旧实现只认 UPPERCASE → 全部落 `_` 默认分支 →
    /// 首页徽标恒为 CET6、难度过滤形同虚设。
    test('服务端小写分类（sync 落地形态）', () {
      const expected = {
        'daily_conversation': 'LOW',
        'scene_description': 'LOW',
        'simple_story': 'LOW',
        'news': 'MEDIUM',
        'expository': 'MEDIUM',
        'argumentative': 'MEDIUM',
        'personal_essay': 'MEDIUM',
        'academic_abstract': 'HIGH',
        'debate_speech': 'HIGH',
        'legal_document': 'HIGH',
        'art_criticism': 'HIGH',
      };
      expected.forEach((category, difficulty) {
        expect(categoryToDifficulty(category), difficulty, reason: category);
      });
    });

    test('大小写/空白归一（UPPERCASE 存量与 lowercase 新量同一套词表）', () {
      expect(categoryToDifficulty('News'), 'MEDIUM');
      expect(categoryToDifficulty(' Scene_Description '), 'LOW');
      expect(categoryToDifficulty('LEGAL_document'), 'HIGH');
    });

    test('历史分类名仍按原难度（存量行不被归一化改动）', () {
      // 本地生成管道时代的两个名字，服务端不再产出但库里仍有行
      expect(categoryToDifficulty('ACADEMIC_EXCERPT'), 'HIGH');
      expect(categoryToDifficulty('academic_excerpt'), 'HIGH');
      expect(categoryToDifficulty('CLASSIC_NOVEL_EXCERPT'), 'HIGH');
    });
  });
}
