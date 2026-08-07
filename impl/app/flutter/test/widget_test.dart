import 'package:contexta/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App 启动渲染 Onboarding（MaterialApp.router + 主题接入）',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MainApp()));
    await tester.pumpAndSettle();

    expect(find.text('Onboarding — 待实现'), findsOneWidget);
  });
}
