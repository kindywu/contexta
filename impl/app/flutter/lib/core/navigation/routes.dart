/// 路由路径（对照 Kotlin navigation/Screen.kt 的 route 字符串）。
/// 常量即完整定位串（带前导 /），可直接用于 GoRoute path 与导航
/// （go/push/initialLocation）。
abstract final class Routes {
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const login = '/login';
  static const reading = '/reading/:articleId';
  static const vocabulary = '/vocabulary';
  static const addWord = '/add_word';
  static const reference = '/reference';
  static const settings = '/settings';

  /// 归一化为完整定位串（对相对路由如 BottomNavTab.route 补前导 /）。
  static String location(String route) =>
      route.startsWith('/') ? route : '/$route';

  static String readingRoute(int articleId) => '/reading/$articleId';
}
