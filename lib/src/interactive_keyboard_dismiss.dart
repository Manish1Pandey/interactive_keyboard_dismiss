import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_channel.dart';
import 'release_decision.dart';

/// Where an interactive keyboard drag currently is.
enum KeyboardDragPhase {
  /// No interaction; the keyboard is wherever the system put it.
  idle,

  /// The finger is inside the keyboard area and the keyboard follows it.
  dragging,

  /// The finger was lifted and the keyboard is springing to its final
  /// position.
  settling,

  /// The keyboard was pushed off-screen and the system is closing it.
  dismissing,
}

/// How the current platform handles an interactive keyboard drag.
enum KeyboardControlMode {
  /// No drag reached the keyboard yet, so the native capability is unknown.
  unknown,

  /// The native side moves the real keyboard with the finger.
  interactive,

  /// The native side cannot move the keyboard (Android < 30, controller
  /// refused, iOS keyboard view not found): the keyboard is dismissed as soon
  /// as the drag enters it.
  dismissOnDrag,

  /// The platform has no software keyboard integration (web, desktop) or the
  /// widget is disabled; the widget is a pass-through.
  unsupported,
}

/// Observable state of an [InteractiveKeyboardDismiss].
///
/// Pass one to [InteractiveKeyboardDismiss.controller] to read the keyboard
/// offset from outside the widget, or read it inside the subtree with
/// [InteractiveKeyboardInset.of]. The widget writes the values; listeners are
/// notified on every change.
class InteractiveKeyboardDismissController extends ChangeNotifier {
  double _offset = 0;
  double _height = 0;
  double _start = 0;
  bool _liveInsets = false;
  KeyboardDragPhase _phase = KeyboardDragPhase.idle;
  KeyboardControlMode _mode = KeyboardControlMode.unknown;

  /// How far (logical px) the keyboard is currently pulled below its resting
  /// position by the user or the settle animation. 0 when idle.
  double get keyboardOffset => _offset;

  /// The keyboard height the platform currently reports through
  /// `FlutterView.viewInsets.bottom`, in logical px.
  double get keyboardHeight => _height;

  /// The height (logical px) of keyboard that is actually visible, i.e. how
  /// much bottom space the layout must keep free right now. Use this instead
  /// of `MediaQuery.viewInsets.bottom` for anything that must move with the
  /// dragged keyboard.
  double get keyboardInset {
    if (_liveInsets || _phase == KeyboardDragPhase.idle) return _height;
    final double visible = math.max(0, _start - _offset);
    // While the system closes the keyboard, follow whichever is lower: the
    // keyboard where the finger left it, or the inset the engine animates.
    return _phase == KeyboardDragPhase.dismissing
        ? math.min(_height, visible)
        : visible;
  }

  /// The current interaction phase.
  KeyboardDragPhase get phase => _phase;

  /// How the platform handled the most recent interaction.
  KeyboardControlMode get mode => _mode;

  /// Whether a drag, settle or dismiss is in progress.
  bool get isInteracting => _phase != KeyboardDragPhase.idle;

  void _set({
    double? offset,
    double? height,
    double? start,
    bool? liveInsets,
    KeyboardDragPhase? phase,
    KeyboardControlMode? mode,
  }) {
    var changed = false;
    if (offset != null && offset != _offset) {
      _offset = offset;
      changed = true;
    }
    if (height != null && height != _height) {
      _height = height;
      changed = true;
    }
    if (start != null && start != _start) {
      _start = start;
      changed = true;
    }
    if (liveInsets != null && liveInsets != _liveInsets) {
      _liveInsets = liveInsets;
      changed = true;
    }
    if (phase != null && phase != _phase) {
      _phase = phase;
      changed = true;
    }
    if (mode != null && mode != _mode) {
      _mode = mode;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

/// Makes the software keyboard follow the finger when a scroll view inside
/// [child] is dragged down into it, like iOS
/// `UIScrollView.keyboardDismissMode = .interactive`.
///
/// When the drag is released the keyboard either springs away (and the focused
/// text field is unfocused) or springs back. Layout inside [child] stays in
/// sync with the keyboard:
/// with [adjustMediaQuery] (the default) `MediaQuery.viewInsets.bottom` below
/// this widget reports the visible keyboard height, so a `Scaffold` placed in
/// [child] resizes as the keyboard moves. [InteractiveKeyboardInset.of],
/// [InteractiveKeyboardInsetBuilder] and [InteractiveKeyboardPadding] give
/// direct access to the same value.
///
/// Place it above both the scroll view and the input bar, for example as the
/// `body` of a `Scaffold(resizeToAvoidBottomInset: false)` or around the whole
/// `Scaffold`.
///
/// Platforms:
/// * iOS: UIKit's own interactive dismissal (the plugin routes the touches in
///   this widget's area to a hidden `UIScrollView` with
///   `keyboardDismissMode = .interactive`); UIKit moves the keyboard and
///   decides dismiss vs. restore, the widget keeps the layout in step.
/// * Android API 30+: `WindowInsetsAnimationController`; the widget decides
///   with [thresholds].
/// * Android 24–29: the keyboard is dismissed as soon as the drag enters it.
/// * Everywhere else it renders [child] unchanged.
class InteractiveKeyboardDismiss extends StatefulWidget {
  /// Creates an interactive keyboard dismiss area around [child].
  const InteractiveKeyboardDismiss({
    super.key,
    required this.child,
    this.enabled = true,
    this.controller,
    this.thresholds = const KeyboardDismissThresholds(),
    this.requireScrollGesture = true,
    this.unfocusOnDismiss = true,
    this.adjustMediaQuery = true,
    this.onDismissed,
    this.onRestored,
  });

  /// The subtree containing the scroll view (and usually the input bar).
  final Widget child;

  /// Whether drags are tracked. When false the widget only passes values
  /// through.
  final bool enabled;

  /// Optional external controller to observe the keyboard offset. When null
  /// the widget creates its own.
  final InteractiveKeyboardDismissController? controller;

  /// Velocity and distance thresholds used on release on Android. On iOS the
  /// system makes this decision itself, exactly like a native scroll view.
  final KeyboardDismissThresholds thresholds;

  /// Android: when true (default) only drags that a `Scrollable` inside
  /// [child] accepted as a vertical scroll are tracked; when false any pointer
  /// drag over [child] that enters the keyboard drives it.
  ///
  /// iOS ignores this flag: UIKit tracks every vertical drag that starts
  /// inside this widget's area, so the widget follows all of them.
  final bool requireScrollGesture;

  /// When true (default) a dismiss unfocuses the primary focus. When false
  /// the keyboard is hidden with `TextInput.hide` and focus is kept (Android;
  /// on iOS the system ends the text input connection when it dismisses the
  /// keyboard, which also removes focus).
  final bool unfocusOnDismiss;

  /// When true (default) `MediaQuery.viewInsets.bottom` seen by [child] is
  /// replaced by the visible keyboard height while an interaction runs.
  final bool adjustMediaQuery;

  /// Called after a drag dismissed the keyboard.
  final VoidCallback? onDismissed;

  /// Called after a released drag put the keyboard back.
  final VoidCallback? onRestored;

  /// Whether this platform can drive the keyboard (iOS and Android, not web).
  static bool get isPlatformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  State<InteractiveKeyboardDismiss> createState() =>
      _InteractiveKeyboardDismissState();
}

class _InteractiveKeyboardDismissState extends State<InteractiveKeyboardDismiss>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  InteractiveKeyboardDismissController? _ownController;
  late final AnimationController _spring;
  final InteractiveKeyboardChannel _channel =
      InteractiveKeyboardChannel.instance;

  int? _pointer;
  VelocityTracker? _tracker;
  bool _scrollDragging = false;
  bool _pointerConsumed = false;

  double _startHeight = 0;
  double _keyboardTop = 0;
  int _generation = 0;
  KeyboardControlSession? _session;
  ({double velocity, bool forceRestore})? _pendingRelease;
  Timer? _dismissTimeout;

  InteractiveKeyboardDismissController get _controller =>
      widget.controller ?? _ownController!;

  bool get _active =>
      widget.enabled && InteractiveKeyboardDismiss.isPlatformSupported;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownController = InteractiveKeyboardDismissController();
    }
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
    WidgetsBinding.instance.addObserver(this);
    _channel.addCancelListener(_onNativeCancelled);
    if (!_active) {
      _controller._set(mode: KeyboardControlMode.unsupported);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHeight();
  }

  @override
  void didUpdateWidget(InteractiveKeyboardDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final InteractiveKeyboardDismissController previous =
          oldWidget.controller ?? _ownController!;
      if (widget.controller == null) {
        _ownController = InteractiveKeyboardDismissController();
      }
      _controller._set(
        offset: previous._offset,
        height: previous._height,
        start: previous._start,
        liveInsets: previous._liveInsets,
        phase: previous._phase,
        mode: previous._mode,
      );
      if (oldWidget.controller == null && widget.controller != null) {
        previous.dispose();
        if (identical(previous, _ownController)) _ownController = null;
      }
    }
    if (!_active) {
      if (_controller.phase == KeyboardDragPhase.dragging ||
          _controller.phase == KeyboardDragPhase.settling) {
        _abort(restoreNative: true);
      }
      _controller._set(mode: KeyboardControlMode.unsupported);
    } else if (_controller.mode == KeyboardControlMode.unsupported) {
      _controller._set(mode: KeyboardControlMode.unknown);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.removeCancelListener(_onNativeCancelled);
    if (_controller.phase == KeyboardDragPhase.dragging ||
        _controller.phase == KeyboardDragPhase.settling) {
      unawaited(_channel.cancel());
    }
    if (_sentRegion != null) unawaited(_channel.setRegion(_regionId, null));
    _generation++;
    _dismissTimeout?.cancel();
    _spring.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    _syncHeight();
    _checkDismissComplete();
    _scheduleRegionSync();
  }

  // ---------------------------------------------------------------- geometry

  FlutterView? get _view => View.maybeOf(context);

  double get _rawKeyboardHeight {
    final FlutterView? view = _view;
    if (view == null || view.devicePixelRatio == 0) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  double get _viewHeight {
    final FlutterView? view = _view;
    if (view == null || view.devicePixelRatio == 0) return 0;
    return view.physicalSize.height / view.devicePixelRatio;
  }

  void _syncHeight() => _controller._set(height: _rawKeyboardHeight);

  // ---------------------------------------------------------------- input

  bool _onScrollNotification(ScrollNotification notification) {
    if (_pointer == null || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final bool userDrag = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (userDrag) _scrollDragging = true;
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_active || _pointer != null) return;
    if (_controller.phase != KeyboardDragPhase.idle) return;
    _pointer = event.pointer;
    _pointerConsumed = false;
    // On iOS the system tracks every vertical drag in the registered region,
    // so the Dart side must follow all of them to stay in sync.
    _scrollDragging =
        !widget.requireScrollGesture ||
        defaultTargetPlatform == TargetPlatform.iOS;
    _scheduleRegionSync();
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _tracker?.addPosition(event.timeStamp, event.position);
    if (!_scrollDragging || _pointerConsumed || !_active) return;
    _handleMove(event.position.dy);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final double velocity = _tracker?.getVelocity().pixelsPerSecond.dy ?? 0;
    _clearPointer();
    if (_controller.phase == KeyboardDragPhase.dragging) {
      _release(velocity: velocity, forceRestore: false);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _clearPointer();
    if (_controller.phase == KeyboardDragPhase.dragging) {
      _release(velocity: 0, forceRestore: true);
    }
  }

  void _clearPointer() {
    _pointer = null;
    _tracker = null;
    _scrollDragging = false;
    _pointerConsumed = false;
  }

  void _handleMove(double pointerY) {
    switch (_controller.phase) {
      case KeyboardDragPhase.idle:
        final double height = _rawKeyboardHeight;
        if (height <= 0) return;
        final double top = _viewHeight - height;
        if (pointerY <= top) return;
        _startInteraction(height: height, top: top);
        _applyPointer(pointerY);
      case KeyboardDragPhase.dragging:
        _applyPointer(pointerY);
      case KeyboardDragPhase.settling:
      case KeyboardDragPhase.dismissing:
        return;
    }
  }

  void _applyPointer(double pointerY) {
    final double offset = keyboardOffsetForPointer(
      pointerY: pointerY,
      keyboardTop: _keyboardTop,
      height: _startHeight,
    );
    _controller._set(offset: offset);
    if (_session?.started ?? false) {
      unawaited(_channel.update(offset / _startHeight));
    }
  }

  // ------------------------------------------------------------- lifecycle

  void _startInteraction({required double height, required double top}) {
    _startHeight = height;
    _keyboardTop = top;
    _session = null;
    _pendingRelease = null;
    _spring.stop();
    _dismissTimeout?.cancel();
    final int generation = ++_generation;
    _controller._set(
      phase: KeyboardDragPhase.dragging,
      liveInsets: defaultTargetPlatform == TargetPlatform.android,
      offset: 0,
      start: height,
    );
    unawaited(
      _channel.begin().then((KeyboardControlSession session) {
        if (!mounted || generation != _generation) return;
        _onSessionReady(session);
      }),
    );
  }

  void _onSessionReady(KeyboardControlSession session) {
    _session = session;
    if (!session.started) {
      _fallbackDismiss();
      return;
    }
    _controller._set(
      mode: KeyboardControlMode.interactive,
      liveInsets: session.liveInsets,
    );
    final ({double velocity, bool forceRestore})? pending = _pendingRelease;
    _pendingRelease = null;
    if (_startHeight > 0) {
      unawaited(_channel.update(_controller.keyboardOffset / _startHeight));
    }
    if (pending != null) {
      _release(velocity: pending.velocity, forceRestore: pending.forceRestore);
    }
  }

  /// Dismiss-on-drag behaviour for platforms that cannot move the keyboard.
  void _fallbackDismiss() {
    _generation++;
    _pendingRelease = null;
    _pointerConsumed = true;
    _controller._set(
      mode: KeyboardControlMode.dismissOnDrag,
      liveInsets: true,
      offset: 0,
      phase: KeyboardDragPhase.idle,
    );
    _hideKeyboard();
    widget.onDismissed?.call();
  }

  void _release({required double velocity, required bool forceRestore}) {
    if (_session == null) {
      _pendingRelease = (velocity: velocity, forceRestore: forceRestore);
      _controller._set(phase: KeyboardDragPhase.settling);
      return;
    }
    final KeyboardControlSession session = _session!;
    if (!session.started) return;
    final double offset = _controller.keyboardOffset;
    final KeyboardReleaseDecision decision = forceRestore
        ? KeyboardReleaseDecision.restore
        : decideKeyboardRelease(
            offset: offset,
            height: _startHeight,
            velocity: velocity,
            thresholds: widget.thresholds,
          );
    final bool dismiss = decision == KeyboardReleaseDecision.dismiss;
    final int generation = _generation;
    _controller._set(phase: KeyboardDragPhase.settling);
    final Future<KeyboardSystemDecision?> nativeDone = _channel.end(
      dismiss: dismiss,
      velocity: _startHeight > 0 ? velocity / _startHeight : 0,
    );

    if (session.systemDriven) {
      // The system decided and is animating the real keyboard; the offset
      // stays where the finger left it until we know which way it went.
      unawaited(
        nativeDone.then((KeyboardSystemDecision? system) {
          if (!mounted || generation != _generation) return;
          final bool dismissed = system?.dismissed ?? dismiss;
          final Future<void> animation;
          if (dismissed) {
            // The engine may drop its inset to 0 at once for an interactive
            // hide, so follow the system's own hide duration instead.
            animation = _animateOffsetTimed(
              offset,
              _startHeight,
              system?.animationDuration ?? Duration.zero,
            );
          } else {
            animation = _animateOffset(offset, 0, velocity);
          }
          unawaited(
            animation.then((_) {
              if (!mounted || generation != _generation) return;
              if (dismissed) {
                _finishDismiss(keepOffset: false);
              } else {
                _finishRestore();
              }
            }),
          );
        }),
      );
      return;
    }

    final double target = dismiss ? _startHeight : 0;
    unawaited(
      Future.wait<void>(<Future<void>>[
        nativeDone,
        _animateOffset(offset, target, velocity),
      ]).then((_) {
        if (!mounted || generation != _generation) return;
        if (dismiss) {
          _finishDismiss(keepOffset: false);
        } else {
          _finishRestore();
        }
      }),
    );
  }

  /// Moves the Dart offset to [to] over [duration] with an ease-out curve
  /// (instantly for a zero duration).
  Future<void> _animateOffsetTimed(double from, double to, Duration duration) {
    if (duration <= Duration.zero) {
      _spring.value = to;
      _controller._set(offset: to);
      return Future<void>.value();
    }
    _spring.value = from;
    return _spring
        .animateTo(to, duration: duration, curve: Curves.easeOutCubic)
        .orCancel
        .catchError((Object _) {});
  }

  /// Runs [keyboardSpring] on the Dart offset; completes when settled or
  /// stopped.
  Future<void> _animateOffset(double from, double to, double velocity) {
    _spring.value = from;
    return _spring
        .animateWith(SpringSimulation(keyboardSpring, from, to, velocity))
        .orCancel
        .catchError((Object _) {});
  }

  void _onSpringTick() {
    if (_controller.phase != KeyboardDragPhase.settling) return;
    _controller._set(offset: _spring.value.clamp(0.0, _startHeight).toDouble());
  }

  void _finishRestore() {
    _controller._set(offset: 0, phase: KeyboardDragPhase.idle);
    widget.onRestored?.call();
  }

  void _finishDismiss({required bool keepOffset}) {
    _controller._set(
      offset: keepOffset ? null : _startHeight,
      phase: KeyboardDragPhase.dismissing,
    );
    _hideKeyboard();
    widget.onDismissed?.call();
    _dismissTimeout?.cancel();
    _dismissTimeout = Timer(const Duration(seconds: 1), _completeDismiss);
    // The keyboard may already be gone (e.g. Android finished hidden).
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkDismissComplete();
    });
  }

  void _checkDismissComplete() {
    if (_controller.phase == KeyboardDragPhase.dismissing &&
        _rawKeyboardHeight <= 0) {
      _completeDismiss();
    }
  }

  void _completeDismiss() {
    _dismissTimeout?.cancel();
    _dismissTimeout = null;
    if (!mounted || _controller.phase != KeyboardDragPhase.dismissing) return;
    _controller._set(offset: 0, phase: KeyboardDragPhase.idle);
  }

  void _hideKeyboard() {
    if (widget.unfocusOnDismiss) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
  }

  void _onNativeCancelled() {
    if (!mounted) return;
    final KeyboardDragPhase phase = _controller.phase;
    if (phase == KeyboardDragPhase.dragging ||
        phase == KeyboardDragPhase.settling) {
      _spring.stop();
      _session = const KeyboardControlSession(started: false, liveInsets: true);
      _fallbackDismiss();
    }
  }

  void _abort({required bool restoreNative}) {
    _generation++;
    _spring.stop();
    _pendingRelease = null;
    _session = null;
    if (restoreNative) unawaited(_channel.cancel());
    _controller._set(offset: 0, phase: KeyboardDragPhase.idle);
  }

  // ---------------------------------------------------------------- region

  Rect? _sentRegion;
  bool _ancestorHadInset = false;
  bool _regionSyncScheduled = false;

  int get _regionId => identityHashCode(this);

  bool get _usesRegions =>
      _active && defaultTargetPlatform == TargetPlatform.iOS;

  /// Tells the platform where this widget is on screen (iOS only), after the
  /// current frame is laid out.
  void _scheduleRegionSync() {
    if (_regionSyncScheduled) return;
    _regionSyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _regionSyncScheduled = false;
      if (mounted) _syncRegion();
    });
  }

  void _syncRegion() {
    Rect? rect;
    if (_usesRegions) {
      final RenderObject? box = context.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) {
        rect = box.localToGlobal(Offset.zero) & box.size;
      }
    }
    if (rect == _sentRegion) return;
    _sentRegion = rect;
    unawaited(_channel.setRegion(_regionId, rect));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _scheduleRegionSync();
    // The widget structure never depends on [enabled], [adjustMediaQuery] or
    // the phase, so toggling them never remounts (and resets) the child.
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: InteractiveKeyboardInset(
          controller: _controller,
          child: ListenableBuilder(
            listenable: _controller,
            builder: _buildMediaQuery,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaQuery(BuildContext context, Widget? child) {
    final MediaQueryData? data = MediaQuery.maybeOf(context);
    if (data == null) return child!;
    final double ancestorBottom = data.viewInsets.bottom;
    final bool interacting =
        widget.adjustMediaQuery && _active && _controller.isInteracting;
    if (!interacting) _ancestorHadInset = ancestorBottom > 0;
    // Only rewrite an inset the ancestors actually pass down (a Scaffold body
    // above us may already have consumed it). During a system dismiss the
    // engine can drop its inset to 0 before the keyboard has moved, so the
    // controller value is used even when it is above the ancestor's.
    final double bottom = interacting && _ancestorHadInset
        ? _controller.keyboardInset
        : ancestorBottom;
    if (bottom == ancestorBottom) return MediaQuery(data: data, child: child!);
    // As the keyboard slides below the home indicator, hand the safe-area
    // padding back gradually, the way the engine derives padding from
    // viewPadding and viewInsets.
    final double padding = math.max(
      data.padding.bottom,
      math.max(0, data.viewPadding.bottom - bottom),
    );
    return MediaQuery(
      data: data.copyWith(
        viewInsets: data.viewInsets.copyWith(bottom: bottom),
        padding: data.padding.copyWith(bottom: padding),
      ),
      child: child!,
    );
  }
}

/// Exposes the [InteractiveKeyboardDismissController] of the nearest
/// [InteractiveKeyboardDismiss] to its subtree.
class InteractiveKeyboardInset
    extends InheritedNotifier<InteractiveKeyboardDismissController> {
  /// Creates the inherited scope. [InteractiveKeyboardDismiss] inserts one;
  /// you normally do not create it yourself.
  const InteractiveKeyboardInset({
    super.key,
    required InteractiveKeyboardDismissController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller of the nearest [InteractiveKeyboardDismiss], or null.
  /// Registers a dependency: the caller rebuilds whenever it changes.
  static InteractiveKeyboardDismissController? controllerOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<InteractiveKeyboardInset>()
      ?.notifier;

  /// The visible keyboard height (logical px) from the nearest
  /// [InteractiveKeyboardDismiss], or null when there is none.
  static double? maybeOf(BuildContext context) =>
      controllerOf(context)?.keyboardInset;

  /// The visible keyboard height (logical px). Falls back to
  /// `MediaQuery.viewInsetsOf(context).bottom` when there is no
  /// [InteractiveKeyboardDismiss] above [context].
  static double of(BuildContext context) =>
      maybeOf(context) ?? MediaQuery.viewInsetsOf(context).bottom;
}

/// Builds a widget from the visible keyboard height of the nearest
/// [InteractiveKeyboardDismiss].
class InteractiveKeyboardInsetBuilder extends StatelessWidget {
  /// Creates a builder. [child] is passed through to [builder] unchanged.
  const InteractiveKeyboardInsetBuilder({
    super.key,
    required this.builder,
    this.child,
  });

  /// Called with the visible keyboard height in logical px.
  final ValueWidgetBuilder<double> builder;

  /// Optional subtree that does not depend on the inset.
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      builder(context, InteractiveKeyboardInset.of(context), child);
}

/// Pads [child] at the bottom by the visible keyboard height, so an input bar
/// sits exactly on top of the (possibly dragged) keyboard.
///
/// Use it with `Scaffold(resizeToAvoidBottomInset: false)`, or when
/// [InteractiveKeyboardDismiss.adjustMediaQuery] is off.
class InteractiveKeyboardPadding extends StatelessWidget {
  /// Creates the padding.
  const InteractiveKeyboardPadding({super.key, required this.child});

  /// The widget to keep above the keyboard.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: InteractiveKeyboardInset.of(context)),
    child: child,
  );
}
