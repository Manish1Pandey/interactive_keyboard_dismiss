import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

/// Thresholds that decide whether a released keyboard drag dismisses the
/// keyboard or springs it back.
@immutable
class KeyboardDismissThresholds {
  /// Creates thresholds.
  ///
  /// [velocityThreshold] is in logical pixels per second and must be
  /// non-negative. [dismissFraction] is the part of the keyboard height
  /// (0..1) the keyboard must have been pulled down for a slow release to
  /// dismiss.
  const KeyboardDismissThresholds({
    this.velocityThreshold = 300,
    this.dismissFraction = 0.5,
  }) : assert(velocityThreshold >= 0),
       assert(dismissFraction >= 0 && dismissFraction <= 1);

  /// A release moving downward at least this fast (logical px/s) always
  /// dismisses; a release moving upward at least this fast always restores.
  final double velocityThreshold;

  /// For releases slower than [velocityThreshold], the keyboard dismisses
  /// when `offset / height >= dismissFraction`.
  final double dismissFraction;

  @override
  bool operator ==(Object other) =>
      other is KeyboardDismissThresholds &&
      other.velocityThreshold == velocityThreshold &&
      other.dismissFraction == dismissFraction;

  @override
  int get hashCode => Object.hash(velocityThreshold, dismissFraction);

  @override
  String toString() =>
      'KeyboardDismissThresholds(velocityThreshold: $velocityThreshold, '
      'dismissFraction: $dismissFraction)';
}

/// What happens to the keyboard when the user lifts the finger.
enum KeyboardReleaseDecision {
  /// Animate the keyboard off-screen and close it.
  dismiss,

  /// Spring the keyboard back to its fully shown position.
  restore,
}

/// Decides what a released keyboard drag does.
///
/// [offset] is how far (logical px) the keyboard was pulled below its resting
/// top edge, [height] the keyboard height at the start of the drag and
/// [velocity] the vertical release velocity in logical px/s (positive means
/// the finger was moving down).
///
/// Rules, in order:
/// 1. `offset <= 0` or `height <= 0` → [KeyboardReleaseDecision.restore].
/// 2. `velocity >= velocityThreshold` → dismiss.
/// 3. `velocity <= -velocityThreshold` → restore.
/// 4. otherwise dismiss when `offset / height >= dismissFraction`.
KeyboardReleaseDecision decideKeyboardRelease({
  required double offset,
  required double height,
  required double velocity,
  KeyboardDismissThresholds thresholds = const KeyboardDismissThresholds(),
}) {
  if (offset <= 0 || height <= 0) return KeyboardReleaseDecision.restore;
  if (velocity >= thresholds.velocityThreshold) {
    return KeyboardReleaseDecision.dismiss;
  }
  if (velocity <= -thresholds.velocityThreshold) {
    return KeyboardReleaseDecision.restore;
  }
  return offset / height >= thresholds.dismissFraction
      ? KeyboardReleaseDecision.dismiss
      : KeyboardReleaseDecision.restore;
}

/// The spring used when a released keyboard settles.
///
/// Critically damped (mass 1, stiffness 400, damping 40): no overshoot, about
/// 95 % of the travel in 0.24 s and fully settled in about 0.45 s, which
/// matches the feel of the system keyboard animation. The iOS side
/// (`UISpringTimingParameters(mass:stiffness:damping:initialVelocity:)`) and
/// the Android side (an analytic spring with the same constants) run the
/// identical physics, so the Dart offset and the real keyboard settle in the
/// same frames.
const SpringDescription keyboardSpring = SpringDescription(
  mass: 1,
  stiffness: 400,
  damping: 40,
);

/// Converts a pointer position into a keyboard offset.
///
/// [pointerY] and [keyboardTop] are global logical coordinates; the result is
/// clamped to `[0, height]`.
double keyboardOffsetForPointer({
  required double pointerY,
  required double keyboardTop,
  required double height,
}) {
  if (height <= 0) return 0;
  return (pointerY - keyboardTop).clamp(0.0, height).toDouble();
}
