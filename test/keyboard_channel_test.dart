import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final InteractiveKeyboardChannel bridge = InteractiveKeyboardChannel.instance;
  final List<MethodCall> calls = <MethodCall>[];

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, (
          MethodCall call,
        ) {
          calls.add(call);
          return handler(call);
        });
  }

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, null);
  });

  test('begin parses the native answer', () async {
    mock(
      (MethodCall call) async => <String, Object>{
        'started': true,
        'liveInsets': true,
      },
    );
    final KeyboardControlSession session = await bridge.begin();
    expect(session.started, isTrue);
    expect(session.liveInsets, isTrue);
    expect(calls.single.method, 'begin');
    expect(session.toString(), contains('started: true'));
  });

  test('begin degrades to not-started on errors and missing plugin', () async {
    mock((MethodCall call) async => throw PlatformException(code: 'x'));
    expect((await bridge.begin()).started, isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, null);
    expect((await bridge.begin()).started, isFalse);
  });

  test('update clamps the fraction, end and cancel pass arguments', () async {
    mock((MethodCall call) async => null);
    await bridge.update(1.7);
    await bridge.update(-2);
    await bridge.end(dismiss: true, velocity: 2.5);
    await bridge.cancel();
    expect(calls.map((MethodCall c) => c.method), <String>[
      'update',
      'update',
      'end',
      'cancel',
    ]);
    expect(calls[0].arguments, <String, Object>{'fraction': 1.0});
    expect(calls[1].arguments, <String, Object>{'fraction': 0.0});
    expect(calls[2].arguments, <String, Object>{
      'dismiss': true,
      'velocity': 2.5,
    });
  });

  test('update/end/cancel swallow platform errors', () async {
    mock((MethodCall call) async => throw PlatformException(code: 'x'));
    await bridge.update(0.5);
    await bridge.end(dismiss: false, velocity: 0);
    await bridge.cancel();
    expect(calls, hasLength(3));
  });

  test(
    'end returns the system decision and setRegion encodes the rect',
    () async {
      mock((MethodCall call) async {
        if (call.method == 'end') {
          return <String, Object>{'dismissed': true, 'duration': 0.25};
        }
        if (call.method == 'begin') {
          return <String, Object>{
            'started': true,
            'liveInsets': false,
            'systemDriven': true,
          };
        }
        return null;
      });
      expect((await bridge.begin()).systemDriven, isTrue);
      final KeyboardSystemDecision? decision = await bridge.end(
        dismiss: false,
        velocity: 0,
      );
      expect(decision!.dismissed, isTrue);
      expect(decision.animationDuration, const Duration(milliseconds: 250));
      expect(decision.toString(), contains('dismissed: true'));
      await bridge.setRegion(7, const Rect.fromLTWH(1, 2, 3, 4));
      await bridge.setRegion(7, null);
      expect(calls[2].arguments, <String, Object>{
        'id': 7,
        'left': 1.0,
        'top': 2.0,
        'width': 3.0,
        'height': 4.0,
      });
      expect(calls[3].arguments, <String, Object>{'id': 7});
    },
  );

  test('end returns null when the platform does not decide', () async {
    mock((MethodCall call) async => null);
    expect(await bridge.end(dismiss: true, velocity: 0), isNull);
  });

  test('diagnostics returns the native map or empty without plugin', () async {
    mock(
      (MethodCall call) async => <String, Object>{
        'platform': 'ios',
        'hostViewCount': 2,
      },
    );
    expect(await bridge.diagnostics(), <String, Object>{
      'platform': 'ios',
      'hostViewCount': 2,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InteractiveKeyboardChannel.channel, null);
    expect(await bridge.diagnostics(), isEmpty);
  });

  test('native onInteractionCancelled reaches listeners', () async {
    int count = 0;
    void listener() => count++;
    bridge.addCancelListener(listener);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          InteractiveKeyboardChannel.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onInteractionCancelled'),
          ),
          (_) {},
        );
    expect(count, 1);
    bridge.removeCancelListener(listener);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          InteractiveKeyboardChannel.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onInteractionCancelled'),
          ),
          (_) {},
        );
    expect(count, 1);
  });
}
