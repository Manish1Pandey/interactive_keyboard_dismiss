import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';

void main() {
  group('decideKeyboardRelease', () {
    const KeyboardDismissThresholds t = KeyboardDismissThresholds(
      velocityThreshold: 300,
      dismissFraction: 0.5,
    );

    KeyboardReleaseDecision decide(double offset, double velocity) =>
        decideKeyboardRelease(
          offset: offset,
          height: 300,
          velocity: velocity,
          thresholds: t,
        );

    test('no pull always restores, even with a fast downward fling', () {
      expect(decide(0, 5000), KeyboardReleaseDecision.restore);
    });

    test('zero keyboard height restores', () {
      expect(
        decideKeyboardRelease(offset: 10, height: 0, velocity: 1000),
        KeyboardReleaseDecision.restore,
      );
    });

    test('fast downward release dismisses even after a tiny pull', () {
      expect(decide(5, 300), KeyboardReleaseDecision.dismiss);
      expect(decide(5, 2000), KeyboardReleaseDecision.dismiss);
    });

    test('fast upward release restores even after a deep pull', () {
      expect(decide(290, -300), KeyboardReleaseDecision.restore);
      expect(decide(290, -2000), KeyboardReleaseDecision.restore);
    });

    test('slow release uses the dismiss fraction (inclusive)', () {
      expect(decide(149, 0), KeyboardReleaseDecision.restore);
      expect(decide(150, 0), KeyboardReleaseDecision.dismiss);
      expect(decide(200, 299), KeyboardReleaseDecision.dismiss);
      expect(decide(100, -299), KeyboardReleaseDecision.restore);
    });

    test('custom thresholds are honoured', () {
      const KeyboardDismissThresholds eager = KeyboardDismissThresholds(
        velocityThreshold: 1000,
        dismissFraction: 0.2,
      );
      expect(
        decideKeyboardRelease(
          offset: 70,
          height: 300,
          velocity: -500,
          thresholds: eager,
        ),
        KeyboardReleaseDecision.dismiss,
      );
      expect(
        decideKeyboardRelease(
          offset: 50,
          height: 300,
          velocity: 900,
          thresholds: eager,
        ),
        KeyboardReleaseDecision.restore,
      );
    });

    test('thresholds value semantics', () {
      expect(
        const KeyboardDismissThresholds(),
        const KeyboardDismissThresholds(
          velocityThreshold: 300,
          dismissFraction: 0.5,
        ),
      );
      expect(
        const KeyboardDismissThresholds().hashCode,
        const KeyboardDismissThresholds().hashCode,
      );
      expect(
        const KeyboardDismissThresholds(dismissFraction: 0.3),
        isNot(const KeyboardDismissThresholds()),
      );
      expect(
        const KeyboardDismissThresholds().toString(),
        contains('dismissFraction: 0.5'),
      );
    });
  });

  group('keyboardOffsetForPointer', () {
    test('is zero above the keyboard and clamps below it', () {
      expect(
        keyboardOffsetForPointer(pointerY: 400, keyboardTop: 500, height: 300),
        0,
      );
      expect(
        keyboardOffsetForPointer(pointerY: 620, keyboardTop: 500, height: 300),
        120,
      );
      expect(
        keyboardOffsetForPointer(pointerY: 900, keyboardTop: 500, height: 300),
        300,
      );
      expect(
        keyboardOffsetForPointer(pointerY: 900, keyboardTop: 500, height: 0),
        0,
      );
    });
  });

  test('keyboardSpring is critically damped and settles in under 0.6 s', () {
    expect(
      keyboardSpring.damping * keyboardSpring.damping,
      closeTo(4 * keyboardSpring.mass * keyboardSpring.stiffness, 1e-9),
    );
    final SpringSimulation sim = SpringSimulation(keyboardSpring, 300, 0, 0);
    expect(sim.x(0.6).abs(), lessThan(0.5));
    // No overshoot.
    for (double t = 0; t < 1; t += 0.01) {
      expect(sim.x(t), greaterThanOrEqualTo(-1e-6));
    }
  });
}
