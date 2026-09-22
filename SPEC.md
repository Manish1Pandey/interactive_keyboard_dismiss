# SPEC — interactive_keyboard_dismiss

## Purpose

Bring iOS `UIScrollView.keyboardDismissMode = .interactive` behaviour to Flutter
(flutter/flutter#57609, Android counterpart flutter/flutter#62876): when the user
drags a scroll view down and the finger crosses into the software keyboard, the
keyboard follows the finger. On release it either dismisses or springs back.
The Flutter layout (for example a chat input bar) moves in step with the
keyboard.

## Revision note (research result, iOS)

The first draft of this spec planned to translate the keyboard's host view
(`UIInputSetHostView` in the keyboard window). Measured on the iOS 26.0
simulator: the transform is applied (the plugin read it back) but **the keyboard
on screen does not move**. Moving the container view, the `UITextEffectsWindow`,
or the engine's built-in screenshot hook (`TextInput.onPointerMoveForInteractiveKeyboard`)
did not work either: from iOS 26 the keyboard is drawn outside the app's view
hierarchy. What works on iOS 18.6 and 26.0 alike is letting UIKit do the job: a
hidden `UIScrollView` with `keyboardDismissMode = .interactive` whose
`panGestureRecognizer` is moved onto the `FlutterView`. The requirements
below describe that design.

## Functional requirements

| ID | Requirement |
|----|-------------|
| FR1 | `InteractiveKeyboardDismiss(child: …)` watches the raw pointer stream over `child` (position and velocity) and, on Android, the scroll notifications that carry drag details. |
| FR2 | The keyboard's top edge is computed from the raw `FlutterView` (`viewInsets.bottom`, `physicalSize`), not from an ancestor `MediaQuery` (a `Scaffold` body has its bottom inset removed). |
| FR3 | When the tracked pointer moves below the keyboard's top edge, an interaction begins. Offset = `pointerY − keyboardTop`, clamped to `[0, keyboardHeight]`. Moving back above the edge sets offset 0 without ending the interaction. |
| FR4 | Android: on release a pure-Dart decision picks **dismiss** or **restore**: velocity ≥ `+velocityThreshold` → dismiss; velocity ≤ `−velocityThreshold` → restore; otherwise dismiss if `offset / height ≥ dismissFraction`. Offset 0 always restores. Pointer cancel restores. |
| FR5 | Android: native settles the IME with a critically damped spring (mass 1, stiffness 400, damping 40), Dart runs the same spring for its offset, then the controller finishes shown/hidden and Dart unfocuses (`unfocusOnDismiss`, default true, else `TextInput.hide`). |
| FR6 | iOS: UIKit moves the real keyboard from the same touch and decides dismiss/restore. Native reports the decision (and the system hide duration) as the result of `end`; Dart springs the layout back (restore) or slides it down over the system duration (dismiss). |
| FR7 | iOS: the widget registers its global rect (`setRegion`); the relocated pan recognizer only begins for vertical pans that start inside a registered rect, never cancels or delays Flutter touches, and is disabled when no rect is registered. |
| FR8 | `InteractiveKeyboardDismissController` exposes `keyboardOffset`, `keyboardHeight`, `keyboardInset` (visible height the layout must avoid), `phase` (idle / dragging / settling / dismissing) and `mode` (unknown / interactive / dismissOnDrag / unsupported). |
| FR9 | `adjustMediaQuery` (default true) rewrites `MediaQuery.viewInsets.bottom` (and gives the bottom safe-area padding back as the keyboard slides away) for `child` while an interaction runs, so a `Scaffold` inside `child` resizes in step. `InteractiveKeyboardInset.of(context)`, `InteractiveKeyboardInsetBuilder` and `InteractiveKeyboardPadding` give explicit access. |
| FR10 | iOS insets are not live during the drag: `keyboardInset = startHeight − offset`; Android insets are live (the engine's IME sync callback) and used directly. |
| FR11 | Fallback (Android < 30, controller cancelled/refused, iOS recognizer not installable): dismiss the keyboard as soon as the drag crosses into it (the `.onDrag` behaviour). A native `onInteractionCancelled` mid-drag triggers the same fallback. |
| FR12 | Web, macOS, Windows, Linux: pure pass-through (no channel traffic). The widget tree shape never changes with `enabled`/`adjustMediaQuery`, so toggling them keeps child state. |
| FR13 | Callbacks `onDismissed`, `onRestored`; `enabled`; configurable `KeyboardDismissThresholds`; `InteractiveKeyboardChannel.diagnostics()` for bug reports. |

## Can / Cannot

| Can | Cannot |
|-----|--------|
| iOS 18 and 26: the real keyboard follows the finger and is dismissed/restored by UIKit's own interactive logic and animation (verified with real, injected touches on the simulator). | Choose the iOS dismiss/restore outcome: UIKit decides; `thresholds` apply to Android only. |
| Android API 30+: drive the IME inset frame by frame (`WindowInsetsAnimationControllerCompat`) and settle it with a spring. | Make Android < 30 interactive: there is no platform API, so the plugin dismisses on drag. |
| Keep the Flutter layout on the keyboard's top edge during the drag on both platforms. | Match the iOS hide animation exactly after release: UIKit's interactive hide is very fast; the layout follows over the reported system duration (≈ 0.25 s), so a short gap can be visible. |
| Work with any `Scrollable`, including reversed chat lists. | Restrict iOS tracking to scroll gestures only: UIKit tracks any vertical drag starting inside the widget's area (`requireScrollGesture` is Android-only). |
| Keep focus on restore. | Keep focus after an iOS dismiss (`unfocusOnDismiss: false`): the system closes the text input connection. |
| Degrade to dismiss-on-drag instead of failing. | Drive floating/undocked keyboards (iPad floating keyboard, Android floating IMEs). |

## Public API sketch

```dart
InteractiveKeyboardDismiss({
  required Widget child,
  bool enabled = true,
  InteractiveKeyboardDismissController? controller,
  KeyboardDismissThresholds thresholds = const KeyboardDismissThresholds(),
  bool requireScrollGesture = true,
  bool unfocusOnDismiss = true,
  bool adjustMediaQuery = true,
  VoidCallback? onDismissed,
  VoidCallback? onRestored,
});

class KeyboardDismissThresholds { double velocityThreshold = 300; double dismissFraction = 0.5; }
enum KeyboardReleaseDecision { dismiss, restore }
KeyboardReleaseDecision decideKeyboardRelease({offset, height, velocity, thresholds});
double keyboardOffsetForPointer({pointerY, keyboardTop, height});
const SpringDescription keyboardSpring;

class InteractiveKeyboardDismissController extends ChangeNotifier {
  double get keyboardOffset; double get keyboardHeight; double get keyboardInset;
  KeyboardDragPhase get phase; KeyboardControlMode get mode; bool get isInteracting;
}

InteractiveKeyboardInset.of(context) / maybeOf(context) / controllerOf(context)
InteractiveKeyboardInsetBuilder(builder: (context, inset, child) => …)
InteractiveKeyboardPadding(child: …)

InteractiveKeyboardChannel.instance: begin(), update(fraction), end(dismiss, velocity) → KeyboardSystemDecision?,
  setRegion(id, rect?), cancel(), diagnostics(), add/removeCancelListener
```

Method channel `interactive_keyboard_dismiss`. Dart → native: `begin` → `{started, liveInsets, systemDriven}`,
`update {fraction}`, `end {dismiss, velocity}` → `{dismissed, duration}` on iOS / null on Android,
`setRegion {id, left?, top?, width?, height?}`, `cancel`, `diagnostics`. Native → Dart: `onInteractionCancelled`.

## Platform matrix

| Platform | Behaviour |
|----------|-----------|
| iOS 13+ (verified 18.6, 26.0 simulators) | Interactive via UIKit (`keyboardDismissMode = .interactive` on a hidden scroll view, pan recognizer on the FlutterView). |
| Android API 30+ (verified API 36 emulator) | Interactive via `WindowInsetsAnimationControllerCompat`. |
| Android API 24–29 | Dismiss-on-drag. |
| Web / macOS / Windows / Linux | Pass-through. |
