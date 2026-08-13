import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth/auth_service.dart';
import '../../ui/addword/add_word_screen.dart';
import '../../ui/auth/login_screen.dart';
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
/// - login 登录页（守卫重定向目标；成功回跳来源）
///
/// 进入 home 即离开 onboarding（路由表不保留 onboarding 子路由；
/// Onboarding 完成时 context.go(home) 等价 popUpTo inclusive 清栈）。
///
/// 登录守卫（[authService] 非 null 时启用，服务端未配置 / 测试不启用）：
/// - onboarding 不拦截（首次引导先于登录）
/// - 状态 unknown → 先 ensureLoggedIn（本地 token 恢复 / 过期静默重登）
/// - 未登录访问内容页 → 重定向 /login?from=<原位置>（登录成功回跳）
/// - 已登录访问 /login → 回 from / 首页
/// 经 [_AuthRefreshListenable] 桥接为 GoRouter.refreshListenable：登录 /
/// 登出 / 被踢状态变更时立即重估重定向，无需手动导航。
GoRouter buildRouter({AuthService? authService}) {
  return GoRouter(
    initialLocation: Routes.onboarding,
    refreshListenable: authService == null
        ? null
        : _AuthRefreshListenable(authService),
    redirect: (context, state) => _authRedirect(authService, state),
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
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
    ],
  );
}

/// AuthService（riverpod StateNotifier 的 Listenable 非 Flutter Listenable）
/// → GoRouter.refreshListenable 桥接：状态变更时通知 router 重估重定向。
/// 订阅在 [dispose] 时解除（GoRouter 重建场景避免残留监听）。
class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(AuthService service) {
    _removeListener = service.addListener((_) => notifyListeners());
  }

  late final void Function() _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}

/// 登录守卫（[auth] 为 null = 本地模式 / 测试，直接放行）。
Future<String?> _authRedirect(AuthService? auth, GoRouterState state) async {
  if (auth == null) return null;
  if (state.matchedLocation == Routes.onboarding) return null;
  if (auth.status == AuthStatus.unknown) {
    // 启动 / 冷启动首跳：恢复本地登录态（读库快；过期静默重登失败也尽快落态）
    await auth.ensureLoggedIn();
  }
  final isLoginPage = state.matchedLocation == Routes.login;
  if (auth.status != AuthStatus.loggedIn) {
    // 未登录访问内容页 → 登录页（带来源，登录成功回跳）
    if (isLoginPage) return null;
    return '${Routes.login}?from=${Uri.encodeComponent(state.matchedLocation)}';
  }
  if (isLoginPage) {
    final from = state.uri.queryParameters['from'];
    return (from == null || from.isEmpty) ? Routes.home : from;
  }
  return null;
}
