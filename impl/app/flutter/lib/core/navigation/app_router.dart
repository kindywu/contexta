import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/addword/add_word_screen.dart';
import '../../ui/home/home_screen.dart';
import '../../ui/reading/reading_screen.dart';
import '../../ui/settings/settings_screen.dart';
import '../../ui/vocabulary/vocabulary_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

/// 应用路由表（对照 Kotlin navigation/NavGraph.kt）：
///
/// - onboarding → home 并清栈（popUpTo onboarding inclusive）
/// - home/vocabulary/reference/settings 为一级页面（底栏 tab）
/// - reading/:articleId 全屏沉浸（不在底栏），返回 pop
/// - add_word 独立页（返回 pop）
///
/// 进入 home 即离开 onboarding（路由表不保留 onboarding 子路由；
/// Onboarding 完成时 context.go(home) 等价 popUpTo inclusive 清栈）。
GoRouter buildRouter() {
  // 页面实现按任务分批落地（Task 21+），未实现的路由用占位页兜底
  Widget placeholder(String label) => _PlaceholderScreen(label: label);

  return GoRouter(
    initialLocation: Routes.onboarding,
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => placeholder('Onboarding'),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => HomeScreen(
              onArticleClick: (articleId) =>
                  context.push(Routes.readingRoute(articleId)),
            ),
          ),
          GoRoute(
            path: Routes.vocabulary,
            builder: (context, state) => VocabularyScreen(
              onBack: () => context.pop(),
              onAddWord: () => context.push(Routes.addWord),
            ),
          ),
          GoRoute(
            path: Routes.reference,
            builder: (context, state) => placeholder('Reference'),
          ),
          GoRoute(
            path: Routes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.reading,
        builder: (context, state) {
          final articleId =
              int.tryParse(state.pathParameters['articleId'] ?? '') ?? -1;
          return ReadingScreen(
            articleId: articleId,
            onBack: () => context.pop(),
          );
        },
      ),
      GoRoute(
        path: Routes.addWord,
        builder: (context, state) =>
            AddWordScreen(onBack: () => context.pop()),
      ),
    ],
  );
}

/// 占位页：任务分批落地前的页面骨架（Task 21+ 逐个替换）。
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          '$label — 待实现',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}
