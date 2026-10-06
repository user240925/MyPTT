import '../encoding/big5_codec.dart';
import 'screen_buffer.dart';

class Glyph {
  const Glyph(this.col, this.width, this.codePoint, this.leftAttr, this.rightAttr);

  final int col;

  /// 1 for half-width, 2 for full-width.
  final int width;
  final int codePoint;
  final int leftAttr;

  /// Differs from [leftAttr] only for a two-colour full-width character.
  final int rightAttr;
}

List<Glyph> glyphsOfRow(ScreenBuffer s, int row, Big5Codec codec) {
  final out = <Glyph>[];
  var col = 0;
  while (col < s.cols) {
    final b = s.byteAt(row, col);
    final a = s.attrAt(row, col);
    if (b < 0x80) {
      out.add(Glyph(col, 1, b, a, a));
      col++;
    } else if (Big5Codec.isLead(b) &&
        col + 1 < s.cols &&
        Big5Codec.isTrail(s.byteAt(row, col + 1))) {
      final cp = codec.decodePair(b, s.byteAt(row, col + 1));
      out.add(Glyph(col, 2, cp, a, s.attrAt(row, col + 1)));
      col += 2;
    } else {
      out.add(Glyph(col, 1, Big5Codec.replacement, a, a));
      col++;
    }
  }
  return out;
}

String rowString(ScreenBuffer s, int row, Big5Codec codec) {
  final out = StringBuffer();
  for (final g in glyphsOfRow(s, row, codec)) {
    out.writeCharCode(g.codePoint);
  }
  return out.toString().trimRight();
}
