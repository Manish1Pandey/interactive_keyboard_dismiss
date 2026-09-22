import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';
import 'package:interactive_keyboard_dismiss_example/main.dart';

void main() {
  testWidgets(
    'dragging the chat list into the keyboard moves the input bar',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      final List<String> calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        InteractiveKeyboardChannel.channel,
        (MethodCall call) async {
          calls.add(call.method);
          if (call.method == 'begin') {
            return <String, Object>{'started': true, 'liveInsets': false};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          InteractiveKeyboardChannel.channel,
          null,
        ),
      );

      await tester.pumpWidget(const ExampleApp());
      await tester.tap(find.byKey(const Key('input')));
      await tester.pump();
      final double restingBottom = tester
          .getBottomLeft(find.byKey(const Key('input')))
          .dy;
      expect(restingBottom, lessThanOrEqualTo(500));

      final TestGesture g = await tester.startGesture(const Offset(200, 200));
      for (int i = 0; i < 45; i++) {
        await g.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      // Finger at y=650: 150 px of keyboard pulled down.
      expect(calls, contains('begin'));
      expect(calls, contains('update'));
      expect(
        tester.getBottomLeft(find.byKey(const Key('input'))).dy,
        closeTo(restingBottom + 150, 0.5),
      );
      expect(
        find.textContaining('phase dragging · mode interactive'),
        findsOneWidget,
      );
      await g.cancel();
      await tester.pumpAndSettle();
      expect(calls, contains('end'));
      expect(find.textContaining('phase idle'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('settings drawer exposes every option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    for (final String label in <String>[
      'enabled',
      'requireScrollGesture',
      'unfocusOnDismiss',
      'adjustMediaQuery',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('velocityThreshold'), findsOneWidget);
    expect(find.textContaining('dismissFraction'), findsOneWidget);
    // Turning adjustMediaQuery off switches the bar to the padding helper.
    await tester.tap(find.text('adjustMediaQuery'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveKeyboardPadding), findsOneWidget);
  });
}
