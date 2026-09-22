/// Interactive (finger-tracking) keyboard dismissal for Flutter scroll views
/// on iOS and Android: the iOS `keyboardDismissMode = .interactive`
/// behaviour, including Android API 30+ via `WindowInsetsAnimationController`.
///
/// Wrap the part of the screen that holds the scroll view and the input bar
/// in an [InteractiveKeyboardDismiss].
library;

export 'src/interactive_keyboard_dismiss.dart';
export 'src/keyboard_channel.dart'
    show
        InteractiveKeyboardChannel,
        KeyboardControlSession,
        KeyboardSystemDecision;
export 'src/release_decision.dart';
