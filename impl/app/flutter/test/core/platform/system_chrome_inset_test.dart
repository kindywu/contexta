import 'package:contexta/core/platform/system_chrome_inset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS 让位 96dp；Android/其余平台 0', () {
    expect(windowControlsLeftInsetFor(isIOS: true), 96);
    expect(windowControlsLeftInsetFor(isIOS: false), 0);
  });
}
