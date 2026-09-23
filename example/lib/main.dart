import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interactive_keyboard_dismiss/interactive_keyboard_dismiss.dart';

void main() => runApp(const ExampleApp());

/// Demo app for `interactive_keyboard_dismiss`.
class ExampleApp extends StatelessWidget {
  /// Creates the demo app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Interactive keyboard dismiss',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ChatScreen(),
    );
  }
}

/// A chat screen whose message list drags the keyboard down, iOS-style.
class ChatScreen extends StatefulWidget {
  /// Creates the chat screen.
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final InteractiveKeyboardDismissController _keyboard =
      InteractiveKeyboardDismissController();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final List<String> _messages = List<String>.generate(
    40,
    (int i) => i.isEven
        ? 'Message #${40 - i}: drag the list down into the keyboard.'
        : 'Reply #${40 - i}: release fast to dismiss, slowly to decide by distance.',
  );

  bool _enabled = true;
  bool _requireScrollGesture = true;
  bool _unfocusOnDismiss = true;
  bool _adjustMediaQuery = true;
  double _velocityThreshold = 300;
  double _dismissFraction = 0.5;
  int _dismissCount = 0;
  int _restoreCount = 0;
  KeyboardDragPhase _lastPhase = KeyboardDragPhase.idle;

  @override
  void initState() {
    super.initState();
    // Logs every phase change, useful when trying the demo from a terminal.
    _keyboard.addListener(() {
      if (_keyboard.phase == _lastPhase) return;
      _lastPhase = _keyboard.phase;
      debugPrint(
        'interactive_keyboard_dismiss: phase ${_keyboard.phase.name} '
        'mode ${_keyboard.mode.name} '
        'offset ${_keyboard.keyboardOffset.toStringAsFixed(1)} '
        'inset ${_keyboard.keyboardInset.toStringAsFixed(1)}',
      );
    });
  }

  @override
  void dispose() {
    _keyboard.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final String value = _text.text.trim();
    if (value.isEmpty) return;
    setState(() => _messages.insert(0, value));
    _text.clear();
  }

  Future<void> _showDiagnostics() async {
    final Map<String, Object?> info = await InteractiveKeyboardChannel.instance
        .diagnostics();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Native diagnostics'),
        content: SingleChildScrollView(
          child: SelectableText(
            info.isEmpty
                ? 'No native side on this platform.'
                : const JsonEncoder.withIndent('  ').convert(info),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget chat = Column(
      children: <Widget>[
        _StatusBar(
          controller: _keyboard,
          dismissed: _dismissCount,
          restored: _restoreCount,
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('messages'),
            reverse: true,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (BuildContext context, int i) =>
                _Bubble(text: _messages[i], mine: i.isEven),
          ),
        ),
        _InputBar(
          controller: _text,
          focusNode: _focus,
          onSend: _send,
          // Without the MediaQuery adjustment the Scaffold does not resize,
          // so the bar pads itself by the live keyboard inset.
          padForKeyboard: !_adjustMediaQuery,
        ),
      ],
    );

    return InteractiveKeyboardDismiss(
      controller: _keyboard,
      enabled: _enabled,
      requireScrollGesture: _requireScrollGesture,
      unfocusOnDismiss: _unfocusOnDismiss,
      adjustMediaQuery: _adjustMediaQuery,
      thresholds: KeyboardDismissThresholds(
        velocityThreshold: _velocityThreshold,
        dismissFraction: _dismissFraction,
      ),
      onDismissed: () {
        debugPrint('interactive_keyboard_dismiss: dismissed');
        setState(() => _dismissCount++);
      },
      onRestored: () {
        debugPrint('interactive_keyboard_dismiss: restored');
        setState(() => _restoreCount++);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: _adjustMediaQuery,
        appBar: AppBar(
          title: const Text('Interactive keyboard'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Native diagnostics',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: _showDiagnostics,
            ),
            Builder(
              builder: (BuildContext context) => IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.tune),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ),
        endDrawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: <Widget>[
                const ListTile(title: Text('Settings')),
                SwitchListTile(
                  title: const Text('enabled'),
                  value: _enabled,
                  onChanged: (bool v) => setState(() => _enabled = v),
                ),
                SwitchListTile(
                  title: const Text('requireScrollGesture'),
                  value: _requireScrollGesture,
                  onChanged: (bool v) =>
                      setState(() => _requireScrollGesture = v),
                ),
                SwitchListTile(
                  title: const Text('unfocusOnDismiss'),
                  value: _unfocusOnDismiss,
                  onChanged: (bool v) => setState(() => _unfocusOnDismiss = v),
                ),
                SwitchListTile(
                  title: const Text('adjustMediaQuery'),
                  subtitle: const Text(
                    'Off: Scaffold does not resize, the input bar uses '
                    'InteractiveKeyboardPadding instead.',
                  ),
                  value: _adjustMediaQuery,
                  onChanged: (bool v) => setState(() => _adjustMediaQuery = v),
                ),
                ListTile(
                  title: Text(
                    'velocityThreshold: ${_velocityThreshold.round()} px/s',
                  ),
                  subtitle: Slider(
                    min: 0,
                    max: 2000,
                    divisions: 40,
                    value: _velocityThreshold,
                    onChanged: (double v) =>
                        setState(() => _velocityThreshold = v),
                  ),
                ),
                ListTile(
                  title: Text(
                    'dismissFraction: ${_dismissFraction.toStringAsFixed(2)}',
                  ),
                  subtitle: Slider(
                    min: 0,
                    max: 1,
                    divisions: 20,
                    value: _dismissFraction,
                    onChanged: (double v) =>
                        setState(() => _dismissFraction = v),
                  ),
                ),
                ListTile(
                  title: Text(
                    'Dismissed $_dismissCount × · restored $_restoreCount ×',
                  ),
                ),
              ],
            ),
          ),
        ),
        body: chat,
      ),
    );
  }
}

/// Live read-out of the controller, so the offset is visible while dragging.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.controller,
    required this.dismissed,
    required this.restored,
  });

  final InteractiveKeyboardDismissController controller;
  final int dismissed;
  final int restored;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = Theme.of(context).textTheme.labelSmall!;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          key: const Key('status'),
          'phase ${controller.phase.name} · mode ${controller.mode.name}\n'
          'offset ${controller.keyboardOffset.toStringAsFixed(1)} · '
          'inset ${controller.keyboardInset.toStringAsFixed(1)} · '
          'keyboard ${controller.keyboardHeight.toStringAsFixed(1)}\n'
          'dismissed $dismissed · restored $restored',
          style: style,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? colors.primaryContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.padForKeyboard,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool padForKeyboard;

  @override
  Widget build(BuildContext context) {
    final Widget bar = Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('input'),
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Type, then drag the messages down',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: onSend,
                tooltip: 'Send',
              ),
            ],
          ),
        ),
      ),
    );
    return padForKeyboard ? InteractiveKeyboardPadding(child: bar) : bar;
  }
}
