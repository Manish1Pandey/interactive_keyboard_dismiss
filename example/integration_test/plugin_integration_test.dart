// On-device checks of the native side. Run on an iOS simulator / Android
// emulator with the software keyboard enabled:
//   flutter test integration_test/plugin_integration_test.dart -d <device>
//
// Integration tests do not receive real touches, so the finger-tracking itself
// is exercised with real (injected) touches against `flutter run`; these
// tests check the native plumbing each platform relies on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';
import 'package:interactive_keyboard_dismiss_example/main.dart';

double _keyboardHeight(WidgetTester tester) =>
    tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) fail('timed out waiting for condition');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _showKeyboard(WidgetTester tester) async {
  await tester.pumpWidget(const ExampleApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('input')));
  await _waitFor(tester, () => _keyboardHeight(tester) > 100);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final InteractiveKeyboardChannel bridge = InteractiveKeyboardChannel.instance;

  testWidgets('native side is ready to drive the keyboard', (
    WidgetTester tester,
  ) async {
    await _showKeyboard(tester);
    final double height = _keyboardHeight(tester);
    final Map<String, Object?> info = await bridge.diagnostics();
    // ignore: avoid_print
    print('IKD keyboard $height diagnostics $info');

    final KeyboardControlSession session = await bridge.begin();
    // ignore: avoid_print
    print('IKD begin $session');
    expect(session.started, isTrue);

    if (Platform.isIOS) {
      expect(session.systemDriven, isTrue);
      expect(info['flutterViewFound'], isTrue);
      expect(info['recognizerInstalled'], isTrue);
      expect(info['recognizerEnabled'], isTrue);
      expect(info['regions'], 1);
      expect(info['keyboardVisible'], isTrue);
      // No UIKit pan happened: the platform reports "not dismissed".
      expect(
        (await bridge.end(dismiss: true, velocity: 0))?.dismissed,
        isFalse,
      );
      expect(_keyboardHeight(tester), height);
    } else {
      expect(session.liveInsets, isTrue);
      await bridge.update(0.5);
      await _waitFor(
        tester,
        () => (_keyboardHeight(tester) - height / 2).abs() < 2,
      );
      // ignore: avoid_print
      print('IKD at 0.5 inset ${_keyboardHeight(tester)}');
      await bridge.end(dismiss: false, velocity: 0);
      await _waitFor(
        tester,
        () => (_keyboardHeight(tester) - height).abs() < 1,
      );
      // ignore: avoid_print
      print('IKD restored inset ${_keyboardHeight(tester)}');

      expect((await bridge.begin()).started, isTrue);
      await bridge.update(0.3);
      await bridge.end(dismiss: true, velocity: 1);
      await _waitFor(tester, () => _keyboardHeight(tester) == 0);
      // ignore: avoid_print
      print('IKD dismissed inset ${_keyboardHeight(tester)}');
    }
  });
}
