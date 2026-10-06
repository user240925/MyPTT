import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';
import 'terminal_painter.dart';

/// Shows a [TerminalSession] and forwards hardware keyboard input to it.
class TerminalView extends StatefulWidget {
  const TerminalView({super.key, required this.session});

  final TerminalSession session;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  static const Duration _blinkInterval = Duration(milliseconds: 600);

  /// 80 columns of 1:2 cells by 24 rows.
  static const double _aspectRatio = 80 / (24 * 2);

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

  final _focus = FocusNode();
  late final StreamSubscription<void> _updates;
  late final Timer _blink;
  bool _blinkOn = true;

  @override
  void initState() {
    super.initState();
    _updates = widget.session.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _blink = Timer.periodic(_blinkInterval, (_) {
      if (mounted) setState(() => _blinkOn = !_blinkOn);
    });
  }

  @override
  void dispose() {
    _blink.cancel();
    _updates.cancel();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
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
    final text = event.character;
    if (text == null || text.isEmpty) return KeyEventResult.ignored;
    session.sendText(text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _focus.requestFocus,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: _aspectRatio,
              child: CustomPaint(
                painter: TerminalPainter(
                  screen: widget.session.screen,
                  codec: widget.session.codec,
                  blinkOn: _blinkOn,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
