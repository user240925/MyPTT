import '../encoding/big5_codec.dart';
import 'row_glyphs.dart';
import 'screen_buffer.dart';

class CellPos {
  const CellPos(this.row, this.col);

  final int row;
  final int col;

  bool isBefore(CellPos other) =>
      row < other.row || (row == other.row && col < other.col);

  @override
  bool operator ==(Object other) =>
      other is CellPos && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'CellPos($row, $col)';
}

/// A run of cells in reading order between two positions, both inclusive.
class Selection {
  const Selection(this.anchor, this.focus);

  /// Where the selection gesture began.
  final CellPos anchor;

  /// Where the finger currently is.
  final CellPos focus;

  CellPos get start => focus.isBefore(anchor) ? focus : anchor;
  CellPos get end => focus.isBefore(anchor) ? anchor : focus;

  /// First and last selected column on [row], or null if the row is outside.
  (int, int)? columnsOnRow(int row, int cols) {
    final s = start, e = end;
    if (row < s.row || row > e.row) return null;
    return (row == s.row ? s.col : 0, row == e.row ? e.col : cols - 1);
  }
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

CellPos _clampPos(ScreenBuffer s, CellPos p) =>
    CellPos(_clamp(p.row, 0, s.rows - 1), _clamp(p.col, 0, s.cols - 1));

String textInRange(ScreenBuffer s, Big5Codec codec, Selection sel) {
  final clamped = Selection(_clampPos(s, sel.start), _clampPos(s, sel.end));
  final lines = <String>[];
  for (var r = clamped.start.row; r <= clamped.end.row; r++) {
    final (from, to) = clamped.columnsOnRow(r, s.cols)!;
    final line = StringBuffer();
    for (final g in glyphsOfRow(s, r, codec)) {
      if (g.col + g.width - 1 >= from && g.col <= to) {
        line.writeCharCode(g.codePoint);
      }
    }
    lines.add(line.toString().trimRight());
  }
  return lines.join('\n');
}

final RegExp _url = RegExp(r'https?://[\x21-\x7E]+');
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]>]+$');

/// A URL on one row and the columns it occupies, both inclusive.
class UrlSpan {
  const UrlSpan(this.url, this.firstCol, this.lastCol);

  final String url;
  final int firstCol;
  final int lastCol;
}

/// Every http(s) URL on [row]. URLs that wrap onto the next row are not
/// joined.
List<UrlSpan> urlSpansOfRow(ScreenBuffer s, Big5Codec codec, int row) {
  if (row < 0 || row >= s.rows) return const [];
  final text = StringBuffer();
  // First and last column of each character in [text].
  final firstCol = <int>[];
  final lastCol = <int>[];
  for (final g in glyphsOfRow(s, row, codec)) {
    // Keep one UTF-16 unit per glyph so string indices match the lists.
    text.writeCharCode(
      g.codePoint > 0xFFFF ? Big5Codec.replacement : g.codePoint,
    );
    firstCol.add(g.col);
    lastCol.add(g.col + g.width - 1);
  }
  final spans = <UrlSpan>[];
  for (final m in _url.allMatches(text.toString())) {
    final url = m.group(0)!.replaceFirst(_trailingPunctuation, '');
    if (url.isEmpty) continue;
    spans.add(
      UrlSpan(url, firstCol[m.start], lastCol[m.start + url.length - 1]),
    );
  }
  return spans;
}

/// The http(s) URL covering [pos], or null.
String? urlAt(ScreenBuffer s, Big5Codec codec, CellPos pos) {
  for (final span in urlSpansOfRow(s, codec, pos.row)) {
    if (pos.col >= span.firstCol && pos.col <= span.lastCol) return span.url;
  }
  return null;
}
