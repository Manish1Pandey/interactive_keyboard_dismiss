# interactive_keyboard_dismiss example

A chat screen showing every feature of the plugin:

- drag the message list down into the keyboard: the keyboard follows the finger
  and the input bar stays on its top edge;
- the status bar shows the live `phase`, `mode`, `keyboardOffset`,
  `keyboardInset` and the dismiss/restore counts;
- the settings drawer (tune icon) toggles `enabled`, `requireScrollGesture`,
  `unfocusOnDismiss` and `adjustMediaQuery` (off switches the input bar to
  `InteractiveKeyboardPadding`), and adjusts the thresholds;
- the bug icon shows `InteractiveKeyboardChannel.diagnostics()`.

Run it with `flutter run` on an iOS simulator/device or an Android emulator/device
with the software keyboard enabled. `integration_test/` checks the native side
on a device.
