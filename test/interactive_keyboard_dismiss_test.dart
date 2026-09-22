import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';

/// Screen 400x800 logical px, keyboard 300 px tall -> keyboard top at y=500.
const double kScreenHeight = 800;
const double kKeyboard = 300;
const double kKeyboardTop = kScreenHeight - kKeyboard;

class _Harness {
  _Harness(this.tester) {
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
  }

  final WidgetTester tester;
  final List<MethodCall> calls = <MethodCall>[];
  final List<Map<Object?, Object?>> regions = <Map<Object?, Object?>>[];
  Object? endResult;
  final FocusNode focus = FocusNode();
  final InteractiveKeyboardDismissController controller =
      InteractiveKeyboardDismissController();
  final ScrollController scroll = ScrollController();
  Duration clock = Duration.zero;
  int dismissed = 0;
  int restored = 0;
  Map<String, Object> beginResult = <String, Object>{
    'started': true,
    'liveInsets': false,
  };

  Iterable<MethodCall> named(String method) =>
      calls.where((MethodCall c) => c.method == method);

  Future<void> pump({
    bool requireScrollGesture = true,
    bool unfocusOnDismiss = true,
    bool enabled = true,
    bool adjustMediaQuery = true,
    ScrollPhysics? physics,
    int itemCount = 60,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, kScreenHeight);
    tester.view.viewInsets = const FakeViewPadding(bottom: kKeyboard);
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, (
          MethodCall call,
        ) async {
          if (call.method == 'setRegion') {
            regions.add(call.arguments as Map<Object?, Object?>);
            return null;
          }
          calls.add(call);
          if (call.method == 'begin') return beginResult;
          if (call.method == 'end') return endResult;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveKeyboardDismiss(
          controller: controller,
          enabled: enabled,
          requireScrollGesture: requireScrollGesture,
          unfocusOnDismiss: unfocusOnDismiss,
          adjustMediaQuery: adjustMediaQuery,
          onDismissed: () => dismissed++,
          onRestored: () => restored++,
          child: Scaffold(
            body: Column(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    physics: physics,
                    itemCount: itemCount,
                    itemBuilder: (BuildContext context, int i) =>
                        SizedBox(height: 40, child: Text('message $i')),
                  ),
                ),
                TextField(key: const Key('input'), focusNode: focus),
              ],
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  }

  /// Advances the fake pointer clock.
  Duration next([int ms = 16]) => clock += Duration(milliseconds: ms);

  double get inputBottom =>
      tester.getBottomLeft(find.byKey(const Key('input'))).dy;

  /// Starts at y=100 and drags straight down to [toY] in 10 px steps,
  /// 16 ms apart (≈625 px/s).
  Future<TestGesture> dragTo(double toY, {double startY = 100}) async {
    final TestGesture g = await tester.startGesture(
      Offset(200, startY),
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(Offset.zero, timeStamp: next());
    double y = startY;
    while (y < toY) {
      final double step = (toY - y).clamp(0, 10).toDouble();
      y += step;
      await g.moveBy(Offset(0, step), timeStamp: next());
      await tester.pump();
    }
    return g;
  }

  /// Holds still long enough for the velocity tracker to report ~0.
  Future<void> holdAndRelease(TestGesture g, {required double y}) async {
    await g.moveTo(Offset(200, y), timeStamp: next(2000));
    await tester.pump();
    await g.up(timeStamp: next(200));
  }
}

void main() {
  final TargetPlatformVariant ios = TargetPlatformVariant.only(
    TargetPlatform.iOS,
  );

  testWidgets('drag above the keyboard never starts an interaction', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop - 10);
    await g.up();
    await tester.pumpAndSettle();
    expect(h.calls, isEmpty);
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.focus.hasFocus, isTrue);
  }, variant: ios);

  testWidgets('keyboard and layout follow the finger (iOS, non-live insets)', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    expect(h.inputBottom, kKeyboardTop);

    final TestGesture g = await h.dragTo(kKeyboardTop + 150);
    await tester.pump();

    expect(h.named('begin'), hasLength(1));
    expect(h.controller.phase, KeyboardDragPhase.dragging);
    expect(h.controller.mode, KeyboardControlMode.interactive);
    expect(h.controller.keyboardOffset, 150);
    expect(h.controller.keyboardInset, 150);
    final double lastFraction =
        (h.named('update').last.arguments as Map<Object?, Object?>)['fraction']!
            as double;
    expect(lastFraction, closeTo(0.5, 1e-9));
    // The Scaffold resized through the adjusted MediaQuery: the input bar
    // sits on the moved keyboard's top edge.
    expect(h.inputBottom, kScreenHeight - 150);

    // Moving back above the keyboard edge keeps the interaction, offset 0.
    await g.moveTo(const Offset(200, 300), timeStamp: h.next());
    await tester.pump();
    expect(h.controller.phase, KeyboardDragPhase.dragging);
    expect(h.controller.keyboardOffset, 0);
    expect(h.inputBottom, kKeyboardTop);
    await g.up();
    await tester.pumpAndSettle();
  }, variant: ios);

  testWidgets('slow release past the dismiss fraction dismisses and unfocuses', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 200);
    await h.holdAndRelease(g, y: kKeyboardTop + 200);
    await tester.pump();

    final MethodCall end = h.named('end').single;
    expect((end.arguments as Map<Object?, Object?>)['dismiss'], isTrue);
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isFalse);
    expect(h.dismissed, 1);
    // Until the system reports the keyboard gone, the inset stays pinned at 0.
    expect(h.controller.phase, KeyboardDragPhase.dismissing);
    expect(h.controller.keyboardInset, 0);
    expect(h.inputBottom, kScreenHeight);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.controller.keyboardOffset, 0);
    expect(h.inputBottom, kScreenHeight);
  }, variant: ios);

  testWidgets('slow release before the dismiss fraction springs back', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 60);
    await h.holdAndRelease(g, y: kKeyboardTop + 60);
    await tester.pump();

    final MethodCall end = h.named('end').single;
    expect((end.arguments as Map<Object?, Object?>)['dismiss'], isFalse);
    expect(h.controller.phase, KeyboardDragPhase.settling);
    await tester.pump(const Duration(milliseconds: 50));
    final double mid = h.controller.keyboardOffset;
    expect(mid, inExclusiveRange(0, 60));
    await tester.pumpAndSettle();
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.controller.keyboardOffset, 0);
    expect(h.focus.hasFocus, isTrue);
    expect(h.restored, 1);
    expect(h.inputBottom, kKeyboardTop);
  }, variant: ios);

  testWidgets('fast downward fling dismisses after a short pull', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 40);
    await g.up(timeStamp: h.next());
    await tester.pump();
    expect(
      (h.named('end').single.arguments as Map<Object?, Object?>)['dismiss'],
      isTrue,
    );
    final double velocity =
        (h.named('end').single.arguments as Map<Object?, Object?>)['velocity']!
            as double;
    // ≈625 px/s over a 300 px keyboard.
    expect(velocity, greaterThan(1));
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isFalse);
  }, variant: ios);

  testWidgets('upward fling restores after a deep pull', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 250);
    for (int i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -15), timeStamp: h.next());
      await tester.pump();
    }
    await g.up(timeStamp: h.next());
    await tester.pump();
    expect(
      (h.named('end').single.arguments as Map<Object?, Object?>)['dismiss'],
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isTrue);
    expect(h.restored, 1);
  }, variant: ios);

  testWidgets('pointer cancel always restores', (WidgetTester tester) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 280);
    await g.cancel();
    await tester.pump();
    expect(
      (h.named('end').single.arguments as Map<Object?, Object?>)['dismiss'],
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isTrue);
  }, variant: ios);

  testWidgets('native refusal falls back to dismiss-on-drag', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester)
      ..beginResult = <String, Object>{'started': false, 'liveInsets': false};
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 100);
    expect(h.controller.mode, KeyboardControlMode.dismissOnDrag);
    expect(h.focus.hasFocus, isFalse);
    expect(h.dismissed, 1);
    expect(h.named('begin'), hasLength(1));
    expect(h.named('update'), isEmpty);
    await g.up();
    await tester.pumpAndSettle();
    expect(h.named('end'), isEmpty);
  }, variant: ios);

  testWidgets('native cancellation mid-drag falls back to dismissing', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 100);
    expect(h.controller.phase, KeyboardDragPhase.dragging);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          InteractiveKeyboardChannel.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onInteractionCancelled'),
          ),
          (_) {},
        );
    await tester.pump();
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.controller.mode, KeyboardControlMode.dismissOnDrag);
    expect(h.focus.hasFocus, isFalse);
    await g.up();
    await tester.pumpAndSettle();
    expect(h.named('end'), isEmpty);
  }, variant: ios);

  testWidgets(
    'Android live insets: layout follows viewInsets, not offset',
    (WidgetTester tester) async {
      final _Harness h = _Harness(tester)
        ..beginResult = <String, Object>{'started': true, 'liveInsets': true};
      await h.pump(physics: const AlwaysScrollableScrollPhysics());
      final TestGesture g = await h.dragTo(kKeyboardTop + 120);
      expect(h.controller.keyboardOffset, 120);
      // The engine has not reported a new inset yet: nothing moves twice.
      expect(h.controller.keyboardInset, kKeyboard);
      // The engine reports the IME inset the native controller set.
      tester.view.viewInsets = const FakeViewPadding(bottom: kKeyboard - 120);
      await tester.pump();
      expect(h.controller.keyboardInset, kKeyboard - 120);
      expect(h.inputBottom, kScreenHeight - (kKeyboard - 120));
      await h.holdAndRelease(g, y: kKeyboardTop + 120);
      await tester.pumpAndSettle();
      expect(h.restored, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('unfocusOnDismiss: false hides the keyboard but keeps focus', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    final List<String> textInput = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (MethodCall call) async {
        textInput.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );
    await h.pump(unfocusOnDismiss: false);
    final TestGesture g = await h.dragTo(kKeyboardTop + 250);
    await h.holdAndRelease(g, y: kKeyboardTop + 250);
    await tester.pumpAndSettle();
    expect(h.focus.hasFocus, isTrue);
    expect(textInput, contains('TextInput.hide'));
    expect(h.dismissed, 1);
  }, variant: ios);

  testWidgets(
    'requireScrollGesture ignores drags a Scrollable did not take',
    (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      // Non-scrollable content with clamping physics: the list refuses drags.
      await h.pump(physics: const ClampingScrollPhysics(), itemCount: 2);
      final TestGesture g = await h.dragTo(kKeyboardTop + 150);
      await g.up();
      await tester.pumpAndSettle();
      expect(h.calls, isEmpty);
      expect(h.focus.hasFocus, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('requireScrollGesture: false tracks any drag', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump(
      physics: const ClampingScrollPhysics(),
      itemCount: 2,
      requireScrollGesture: false,
    );
    final TestGesture g = await h.dragTo(kKeyboardTop + 150);
    expect(h.named('begin'), hasLength(1));
    expect(h.controller.keyboardOffset, 150);
    await g.up();
    await tester.pumpAndSettle();
  }, variant: ios);

  testWidgets('adjustMediaQuery: false leaves MediaQuery alone; padding helper '
      'and builder still get the inset', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, kScreenHeight);
    tester.view.viewInsets = const FakeViewPadding(bottom: kKeyboard);
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, (
          MethodCall call,
        ) async {
          if (call.method == 'begin') {
            return <String, Object>{'started': true, 'liveInsets': false};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, null),
    );
    double? built;
    double? mediaQueryBottom;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: InteractiveKeyboardDismiss(
            adjustMediaQuery: false,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    itemCount: 60,
                    itemBuilder: (BuildContext context, int i) =>
                        SizedBox(height: 40, child: Text('m $i')),
                  ),
                ),
                Builder(
                  builder: (BuildContext context) {
                    mediaQueryBottom = MediaQuery.viewInsetsOf(context).bottom;
                    return const SizedBox.shrink();
                  },
                ),
                InteractiveKeyboardInsetBuilder(
                  builder: (BuildContext context, double inset, Widget? c) {
                    built = inset;
                    return c!;
                  },
                  child: const SizedBox.shrink(),
                ),
                const InteractiveKeyboardPadding(
                  child: SizedBox(key: Key('bar'), height: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(built, kKeyboard);
    expect(tester.getBottomLeft(find.byKey(const Key('bar'))).dy, kKeyboardTop);

    final TestGesture g = await tester.startGesture(const Offset(200, 100));
    for (int i = 0; i < 50; i++) {
      await g.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    // Pointer at y=600 -> 100 px pulled.
    expect(built, kKeyboard - 100);
    expect(mediaQueryBottom, kKeyboard);
    expect(
      tester.getBottomLeft(find.byKey(const Key('bar'))).dy,
      kScreenHeight - (kKeyboard - 100),
    );
    await g.cancel();
    await tester.pumpAndSettle();
    expect(built, kKeyboard);
  }, variant: ios);

  testWidgets('safe-area padding comes back as the keyboard slides away', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    EdgeInsets padding() =>
        MediaQuery.paddingOf(tester.element(find.byKey(const Key('input'))));
    expect(padding().bottom, 0);
    final TestGesture g = await h.dragTo(kKeyboardTop + 290);
    // 10 px of keyboard left visible -> 24 px of the 34 px safe area.
    expect(h.controller.keyboardInset, 10);
    expect(padding().bottom, 24);
    await g.cancel();
    await tester.pumpAndSettle();
    expect(padding().bottom, 0);
  }, variant: ios);

  testWidgets('iOS system-driven dismiss follows the system decision and '
      'animates the layout down even if the engine inset drops at once', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester)
      ..beginResult = <String, Object>{
        'started': true,
        'liveInsets': false,
        'systemDriven': true,
      }
      // The system dismisses even though the Dart thresholds would restore.
      ..endResult = <String, Object>{'dismissed': true, 'duration': 0.2};
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 60);
    await h.holdAndRelease(g, y: kKeyboardTop + 60);
    await tester.pump();
    // The engine reports the keyboard gone immediately.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(h.controller.phase, KeyboardDragPhase.settling);
    final double mid = h.controller.keyboardInset;
    expect(mid, inExclusiveRange(0, kKeyboard - 60));
    expect(h.inputBottom, closeTo(kScreenHeight - mid, 0.01));
    await tester.pumpAndSettle();
    expect(h.dismissed, 1);
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.controller.keyboardInset, 0);
    expect(h.inputBottom, kScreenHeight);
  }, variant: ios);

  testWidgets('iOS system-driven restore springs the layout back', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester)
      ..beginResult = <String, Object>{
        'started': true,
        'liveInsets': false,
        'systemDriven': true,
      }
      ..endResult = <String, Object>{'dismissed': false};
    await h.pump();
    final TestGesture g = await h.dragTo(kKeyboardTop + 250);
    await h.holdAndRelease(g, y: kKeyboardTop + 250);
    await tester.pumpAndSettle();
    expect(h.controller.phase, KeyboardDragPhase.idle);
    expect(h.restored, 1);
    expect(h.dismissed, 0);
    expect(h.focus.hasFocus, isTrue);
    expect(h.inputBottom, kKeyboardTop);
  }, variant: ios);

  testWidgets('iOS registers the widget region and removes it on dispose', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    await tester.pump();
    expect(h.regions, isNotEmpty);
    final Map<Object?, Object?> last = h.regions.last;
    expect(last['left'], 0);
    expect(last['top'], 0);
    expect(last['width'], 400);
    expect(last['height'], kScreenHeight);
    await tester.pumpWidget(const SizedBox());
    expect(h.regions.last.containsKey('left'), isFalse);
  }, variant: ios);

  testWidgets(
    'Android never registers regions',
    (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.pump();
      await tester.pump();
      expect(h.regions, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('InteractiveKeyboardInset.of falls back to MediaQuery', (
    WidgetTester tester,
  ) async {
    double? value;
    double? maybe;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 42)),
        child: Builder(
          builder: (BuildContext context) {
            value = InteractiveKeyboardInset.of(context);
            maybe = InteractiveKeyboardInset.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(value, 42);
    expect(maybe, isNull);
  }, variant: ios);

  testWidgets(
    'unsupported platform is a pass-through',
    (WidgetTester tester) async {
      final _Harness h = _Harness(tester);
      await h.pump();
      expect(h.controller.mode, KeyboardControlMode.unsupported);
      final TestGesture g = await h.dragTo(kKeyboardTop + 200);
      await g.up();
      await tester.pumpAndSettle();
      expect(h.calls, isEmpty);
      // (Desktop text fields unfocus on any tap outside; not our concern.)
      expect(h.controller.phase, KeyboardDragPhase.idle);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('disabled widget is a pass-through', (WidgetTester tester) async {
    final _Harness d = _Harness(tester);
    await d.pump(enabled: false);
    expect(d.controller.mode, KeyboardControlMode.unsupported);
    final TestGesture g = await d.dragTo(kKeyboardTop + 200);
    await g.up();
    await tester.pumpAndSettle();
    expect(d.calls, isEmpty);
  }, variant: ios);

  testWidgets('toggling enabled keeps the child state', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness(tester);
    await h.pump();
    h.scroll.jumpTo(200);
    await h.pump(enabled: false);
    expect(h.scroll.offset, 200);
    expect(h.focus.hasFocus, isTrue);
    await h.pump();
    expect(h.scroll.offset, 200);
    expect(h.controller.mode, isNot(KeyboardControlMode.unsupported));
  }, variant: ios);
}
