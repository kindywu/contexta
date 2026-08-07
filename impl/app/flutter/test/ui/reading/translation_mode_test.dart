import 'package:contexta/ui/reading/translation_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// 译文模式循环测试（移植 TranslationModeTest.kt）。
void main() {
  test('cycle order is FULL to DIM to BLURRED to HIDDEN back to FULL', () {
    expect(TranslationMode.full.next, TranslationMode.dim);
    expect(TranslationMode.dim.next, TranslationMode.blurred);
    expect(TranslationMode.blurred.next, TranslationMode.hidden);
    expect(TranslationMode.hidden.next, TranslationMode.full);
  });
}
