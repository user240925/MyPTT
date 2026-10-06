import 'package:flutter/widgets.dart';

import '../core/encoding/big5_codec.dart';
import '../core/terminal/row_glyphs.dart';
import '../core/terminal/screen_buffer.dart';
import 'glyph_shapes.dart';
import 'palette.dart';

/// Paints a [ScreenBuffer]. Every glyph is centred in its own cell, so column
/// alignment does not depend on the font's advance widths.
class TerminalPainter extends CustomPainter {
  TerminalPainter({
    required this.screen,
    required this.codec,
    required this.blinkOn,
  });

  final ScreenBuffer screen;
  final Big5Codec codec;

  /// Whether blinking text is in its visible phase.
  final bool blinkOn;

  static const int _maxCachedGlyphs = 4000;
  static const List<String> _fonts = [
    'MingLiU', 'Microsoft JhengHei', 'PingFang TC', 'Heiti TC', 'monospace',
  ];
  static final Map<(int, Color, double), TextPainter> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / screen.cols, ch = size.height / screen.rows;
    if (cw <= 0 || ch <= 0) return;
    final bgPaint = Paint()..isAntiAlias = false;

    for (var r = 0; r < screen.rows; r++) {
      final top = r * ch;

      var start = 0;
      while (start < screen.cols) {
        final bg = backgroundOf(screen.attrAt(r, start));
        var end = start + 1;
        while (end < screen.cols && backgroundOf(screen.attrAt(r, end)) == bg) {
          end++;
        }
        // Overdraw by half a pixel so rounding never leaves a seam.
        canvas.drawRect(
          Rect.fromLTRB(start * cw, top, end * cw + 0.5, top + ch + 0.5),
          bgPaint..color = bg,
        );
        start = end;
      }

      for (final g in glyphsOfRow(screen, r, codec)) {
        if (g.codePoint == 0x20 || g.codePoint == 0x3000) continue;
        final box = Rect.fromLTWH(g.col * cw, top, g.width * cw, ch);
        final left = _visibleFg(g.leftAttr), right = _visibleFg(g.rightAttr);
        if (g.width == 1 || left == right) {
          if (left != null) _draw(canvas, box, g.codePoint, left);
        } else {
          final mid = box.left + cw;
          _drawClipped(canvas, box, g.codePoint, left,
              Rect.fromLTRB(box.left, box.top, mid, box.bottom));
          _drawClipped(canvas, box, g.codePoint, right,
              Rect.fromLTRB(mid, box.top, box.right, box.bottom));
        }
      }
    }
  }

  Color? _visibleFg(int attr) =>
      (attr & Attr.blink) != 0 && !blinkOn ? null : foregroundOf(attr);

  void _drawClipped(Canvas canvas, Rect box, int cp, Color? color, Rect clip) {
    if (color == null) return;
    canvas.save();
    canvas.clipRect(clip);
    _draw(canvas, box, cp, color);
    canvas.restore();
  }

  void _draw(Canvas canvas, Rect box, int cp, Color color) {
    if (drawShape(canvas, box, cp, color)) return;
    final fontSize = box.height * 0.82;
    if (fontSize < 1) return;
    final tp = _painterFor(cp, color, fontSize);
    tp.paint(
      canvas,
      Offset(
        box.left + (box.width - tp.width) / 2,
        box.top + (box.height - tp.height) / 2,
      ),
    );
  }

  TextPainter _painterFor(int cp, Color color, double fontSize) {
    final key = (cp, color, fontSize);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _maxCachedGlyphs) {
      for (final p in _cache.values) {
        p.dispose();
      }
      _cache.clear();
    }
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(cp),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          height: 1,
          fontFamilyFallback: _fonts,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return _cache[key] = tp;
  }

  @override
  bool shouldRepaint(TerminalPainter oldDelegate) => true;
}
