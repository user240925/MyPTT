import 'dart:ui';

import '../core/terminal/screen_buffer.dart';

/// The 16 ANSI colours: 0–7 normal, 8–15 bright.
const List<Color> ansiPalette = [
  Color(0xFF000000), Color(0xFF800000), Color(0xFF008000), Color(0xFF808000),
  Color(0xFF000080), Color(0xFF800080), Color(0xFF008080), Color(0xFFC0C0C0),
  Color(0xFF808080), Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFFF00),
  Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFFFFFF),
];

bool _inverse(int attr) => (attr & Attr.inverse) != 0;

Color foregroundOf(int attr) {
  if (_inverse(attr)) return ansiPalette[Attr.bg(attr)];
  final bright = (attr & Attr.bright) != 0 ? 8 : 0;
  return ansiPalette[Attr.fg(attr) + bright];
}

Color backgroundOf(int attr) =>
    ansiPalette[_inverse(attr) ? Attr.fg(attr) : Attr.bg(attr)];
