import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of asking the platform to take control of the keyboard.
@immutable
class KeyboardControlSession {
  /// Creates a session result.
  const KeyboardControlSession({
    required this.started,
    required this.liveInsets,
    this.systemDriven = false,
  });

  /// Whether the platform took (or is taking) control of the keyboard. When
  /// false the caller must fall back to dismissing the keyboard.
  final bool started;

  /// Whether the platform reports the moving keyboard through
  /// `FlutterView.viewInsets` while it is controlled (Android). When false
  /// (iOS) the view insets stay at the resting keyboard height and the
  /// visible keyboard height is `viewInsets.bottom - offset`.
  final bool liveInsets;

  /// Whether the operating system itself moves the keyboard from the same
  /// touch and decides between dismiss and restore (iOS). The decision is
  /// returned by [InteractiveKeyboardChannel.end]; `update` calls are ignored.
  final bool systemDriven;

  @override
  String toString() =>
      'KeyboardControlSession(started: $started, liveInsets: $liveInsets, '
      'systemDriven: $systemDriven)';
}

/// What the operating system did with a released keyboard drag (iOS).
@immutable
class KeyboardSystemDecision {
  /// Creates a decision.
  const KeyboardSystemDecision({
    required this.dismissed,
    this.animationDuration = Duration.zero,
  });

  /// True when the system closed the keyboard, false when it put it back.
  final bool dismissed;

  /// Duration of the system's closing animation (zero when unknown or when
  /// the keyboard was put back).
  final Duration animationDuration;

  @override
  String toString() =>
      'KeyboardSystemDecision(dismissed: $dismissed, '
      'animationDuration: $animationDuration)';
}

/// Low-level bridge to the native keyboard controllers.
///
/// Most apps never use this directly; `InteractiveKeyboardDismiss` drives it.
class InteractiveKeyboardChannel {
  InteractiveKeyboardChannel._() {
    channel.setMethodCallHandler(_handle);
  }

  /// The shared instance.
  static final InteractiveKeyboardChannel instance =
      InteractiveKeyboardChannel._();

  /// The method channel used to talk to the platform.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'interactive_keyboard_dismiss',
  );

  final List<VoidCallback> _cancelListeners = <VoidCallback>[];

  /// Registers [listener], called when the platform aborts an interaction on
  /// its own (for example Android cancelled the inset controller).
  void addCancelListener(VoidCallback listener) =>
      _cancelListeners.add(listener);

  /// Removes a listener added with [addCancelListener].
  void removeCancelListener(VoidCallback listener) =>
      _cancelListeners.remove(listener);

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'onInteractionCancelled') {
      for (final VoidCallback listener in List<VoidCallback>.of(
        _cancelListeners,
      )) {
        listener();
      }
    }
    return null;
  }

  /// Asks the platform to take control of the visible keyboard.
  ///
  /// Never throws: a missing implementation or platform error yields
  /// `started: false`.
  Future<KeyboardControlSession> begin() async {
    try {
      final Map<Object?, Object?>? result = await channel
          .invokeMapMethod<Object?, Object?>('begin');
      return KeyboardControlSession(
        started: result?['started'] == true,
        liveInsets: result?['liveInsets'] == true,
        systemDriven: result?['systemDriven'] == true,
      );
    } on PlatformException {
      return const KeyboardControlSession(started: false, liveInsets: false);
    } on MissingPluginException {
      return const KeyboardControlSession(started: false, liveInsets: false);
    }
  }

  /// Moves the controlled keyboard. [fraction] is the pulled-down part of the
  /// keyboard height: 0 is fully shown, 1 fully hidden.
  Future<void> update(double fraction) async {
    try {
      await channel.invokeMethod<void>('update', <String, Object>{
        'fraction': fraction.clamp(0.0, 1.0).toDouble(),
      });
    } on PlatformException {
      // The interaction ended natively; the next begin() starts a new one.
    } on MissingPluginException {
      // No native side on this platform.
    }
  }

  /// Ends the interaction: animates the keyboard away when [dismiss] is true,
  /// back to rest otherwise. [velocity] is the release velocity as a fraction
  /// of the keyboard height per second (positive = downward). Completes when
  /// the native animation has finished.
  ///
  /// For a [KeyboardControlSession.systemDriven] session the platform ignores
  /// [dismiss] and returns its own [KeyboardSystemDecision]. Otherwise
  /// returns null.
  Future<KeyboardSystemDecision?> end({
    required bool dismiss,
    required double velocity,
  }) async {
    try {
      final Map<Object?, Object?>? result = await channel
          .invokeMapMethod<Object?, Object?>('end', <String, Object>{
            'dismiss': dismiss,
            'velocity': velocity,
          });
      final Object? dismissed = result?['dismissed'];
      if (dismissed is! bool) return null;
      final Object? seconds = result?['duration'];
      return KeyboardSystemDecision(
        dismissed: dismissed,
        animationDuration: Duration(
          microseconds: seconds is num ? (seconds * 1e6).round() : 0,
        ),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Registers (or with a null [rect], removes) the global screen area of an
  /// `InteractiveKeyboardDismiss` widget, in logical pixels. On iOS the
  /// system keyboard tracking only starts for touches inside a registered
  /// area. Other platforms ignore it.
  Future<void> setRegion(int id, Rect? rect) async {
    try {
      await channel.invokeMethod<void>('setRegion', <String, Object?>{
        'id': id,
        if (rect != null) ...<String, Object>{
          'left': rect.left,
          'top': rect.top,
          'width': rect.width,
          'height': rect.height,
        },
      });
    } on PlatformException {
      // Nothing registered.
    } on MissingPluginException {
      // No native side on this platform.
    }
  }

  /// Returns what the native side can see of the keyboard, for bug reports
  /// and for checking support on a new OS version.
  ///
  /// iOS: `systemVersion`, whether the tracking recognizer is installed and
  /// enabled, registered region count, keyboard visibility/frame and the
  /// window classes. Android: `sdkInt`, `imeVisible`, `imeBottomPx`,
  /// `interactiveSupported` and `controlling`.
  /// Returns an empty map on platforms without a native side.
  Future<Map<String, Object?>> diagnostics() async {
    try {
      final Map<String, Object?>? result = await channel
          .invokeMapMethod<String, Object?>('diagnostics');
      return result ?? const <String, Object?>{};
    } on MissingPluginException {
      return const <String, Object?>{};
    }
  }

  /// Aborts the interaction immediately and puts the keyboard back at rest.
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Already idle.
    } on MissingPluginException {
      // No native side on this platform.
    }
  }
}
