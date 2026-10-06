import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';

/// The text field that receives the system keyboard, IME, and hardware keys
/// and forwards them to the BBS.
///
/// iOS keyboard behaviour that cannot be checked on Windows lives here.
class InputStrip extends StatefulWidget {
  const InputStrip({
    super.key,
    required this.session,
    required this.focusNode,
    required this.ctrlLatch,
  });

  final TerminalSession session;
  final FocusNode focusNode;

  /// When true, the next single letter typed is sent as a Ctrl combination.
  final ValueNotifier<bool> ctrlLatch;

  @override
  State<InputStrip> createState() => _InputStripState();
}

class _InputStripState extends State<InputStrip> {
  /// A zero-width character kept in the field so that Backspace on a soft
  /// keyboard, which produces no key event, shows up as a deletion.
  static const String _sentinel = '\u200B';
  static const TextEditingValue _blank = TextEditingValue(
    text: _sentinel,
    selection: TextSelection.collapsed(offset: 1),
  );

  static final Map<LogicalKeyboardKey, TermKey> _keys = {
    LogicalKeyboardKey.arrowUp: TermKey.up,
    LogicalKeyboardKey.arrowDown: TermKey.down,
    LogicalKeyboardKey.arrowRight: TermKey.right,
    LogicalKeyboardKey.arrowLeft: TermKey.left,
    LogicalKeyboardKey.enter: TermKey.enter,
    LogicalKeyboardKey.numpadEnter: TermKey.enter,
    LogicalKeyboardKey.backspace: TermKey.backspace,
    LogicalKeyboardKey.tab: TermKey.tab,
    LogicalKeyboardKey.escape: TermKey.escape,
    LogicalKeyboardKey.home: TermKey.home,
    LogicalKeyboardKey.end: TermKey.end,
    LogicalKeyboardKey.pageUp: TermKey.pageUp,
    LogicalKeyboardKey.pageDown: TermKey.pageDown,
    LogicalKeyboardKey.insert: TermKey.insert,
    LogicalKeyboardKey.delete: TermKey.delete,
  };

  final _controller = TextEditingController.fromValue(_blank);
  bool _resetting = false;

  /// Text held back because it contains characters PTT cannot store.
  String? _pending;
  int _pendingUnsupported = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _composing {
    final c = _controller.value.composing;
    return c.isValid && !c.isCollapsed;
  }

  void _reset() {
    _resetting = true;
    _controller.value = _blank;
    _resetting = false;
  }

  void _onChanged() {
    if (_resetting || _composing) return;
    final text = _controller.text;
    if (text == _sentinel) return;
    _reset();
    if (text.isEmpty) {
      widget.session.sendBytes(bytesForKey(TermKey.backspace));
    } else {
      _submit(text.replaceAll(_sentinel, ''));
    }
  }

  void _submit(String text) {
    if (text.isEmpty) return;
    final session = widget.session;

    if (widget.ctrlLatch.value) {
      widget.ctrlLatch.value = false;
      final bytes = bytesForCtrl(text);
      if (bytes != null) {
        session.sendBytes(bytes);
        return;
      }
    }

    // Text typed while a confirmation is showing joins it, so nothing is
    // lost or sent out of order.
    final held = _pending;
    final combined = held == null ? text : held + text;
    final unsupported = session.codec.encode(combined).unmappable;
    if (unsupported > 0) {
      setState(() {
        _pending = combined;
        _pendingUnsupported = unsupported;
      });
      return;
    }
    session.sendText(text);
  }

  void _resolvePending({required bool send}) {
    final text = _pending;
    setState(() => _pending = null);
    if (send && text != null) widget.session.sendText(text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _composing) return KeyEventResult.ignored;
    final session = widget.session;

    final key = _keys[event.logicalKey];
    if (key != null) {
      session.sendBytes(bytesForKey(key));
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      final bytes = bytesForCtrl(event.logicalKey.keyLabel);
      if (bytes == null) return KeyEventResult.ignored;
      session.sendBytes(bytes);
      return KeyEventResult.handled;
    }
    // Printable characters arrive through the text field instead.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('有 $_pendingUnsupported 個字 PTT 不支援，將以 ? 取代'),
                ),
                TextButton(
                  onPressed: () => _resolvePending(send: false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => _resolvePending(send: true),
                  child: const Text('送出'),
                ),
              ],
            ),
          ),
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              // Keep focus so the keyboard stays open after Enter.
              onEditingComplete: () {},
              // Quotes and dashes must reach the BBS as typed.
              smartQuotesType: SmartQuotesType.disabled,
              smartDashesType: SmartDashesType.disabled,
              onSubmitted: (_) {
                // While composing, the action key belongs to the IME.
                if (_composing) return;
                widget.session.sendBytes(bytesForKey(TermKey.enter));
              },
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '輸入 ',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
