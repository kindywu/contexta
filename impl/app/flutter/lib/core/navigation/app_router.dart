import 'package:go_router/go_router.dart';

import '../../ui/addword/add_word_screen.dart';
import '../../ui/home/home_screen.dart';
import '../../ui/onboarding/onboarding_screen.dart';
import '../../ui/reading/reading_screen.dart';
import '../../ui/reference/reference_screen.dart';
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
  return GoRouter(
    initialLocation: Routes.onboarding,
    routes: [
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => OnboardingScreen(
          // 完成引导后清栈跳首页（等价 Kotlin popUpTo onboarding inclusive）
          onComplete: () => context.go(Routes.home),
        ),
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
              // context.go 进入（底栏切换）不留栈，pop 无法返回；回退 = 到首页
              onBack: () => context.go(Routes.home),
              onAddWord: () => context.push(Routes.addWord),
            ),
          ),
          GoRoute(
            path: Routes.reference,
            builder: (context, state) => const ReferenceScreen(),
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
