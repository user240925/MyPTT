import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/terminal/term_keys.dart';

/// A scrollable row of the keys a soft keyboard lacks.
class KeyBar extends StatelessWidget {
  const KeyBar({super.key, required this.session, required this.ctrlLatch});

  final TerminalSession session;

  /// Toggled by the Ctrl button; consumed by the input strip.
  final ValueNotifier<bool> ctrlLatch;

  static const double _height = 44;
  static const List<(String, TermKey)> _keys = [
    ('←', TermKey.left),
    ('↑', TermKey.up),
    ('↓', TermKey.down),
    ('→', TermKey.right),
    ('Enter', TermKey.enter),
    ('PgUp', TermKey.pageUp),
    ('PgDn', TermKey.pageDown),
    ('Home', TermKey.home),
    ('End', TermKey.end),
    ('Esc', TermKey.escape),
    ('Tab', TermKey.tab),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      // Buttons must not take focus, or the soft keyboard would close.
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: [
            for (final (label, key) in _keys)
              _KeyButton(
                label: label,
                onPressed: () => session.sendBytes(bytesForKey(key)),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: ctrlLatch,
              builder: (context, latched, _) => _KeyButton(
                label: 'Ctrl',
                selected: latched,
                onPressed: () => ctrlLatch.value = !ctrlLatch.value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 36),
          backgroundColor: selected ? Colors.white24 : Colors.white10,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
