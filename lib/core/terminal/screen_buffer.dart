import 'dart:typed_data';

/// Attribute bits stored for each column.
abstract final class Attr {
  static const int fgMask = 0x07;
  static const int bright = 0x08;
  static const int bgShift = 4;
  static const int bgMask = 0x70;
  static const int blink = 0x80;
  static const int underline = 0x100;
  static const int inverse = 0x200;

  /// Light grey on black.
  static const int normal = 0x07;

  static int fg(int a) => a & fgMask;
  static int bg(int a) => (a & bgMask) >> bgShift;
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// A grid of raw bytes plus attributes, one entry per column. A full-width
/// character occupies two columns, one byte each, so its halves can carry
/// different attributes.
class ScreenBuffer {
  ScreenBuffer({this.cols = 80, this.rows = 24})
      : bytes = Uint8List(cols * rows),
        attrs = Uint16List(cols * rows),
        scrollBottom = rows - 1 {
    _blank(0, cols * rows);
  }

  final int cols;
  final int rows;
  final Uint8List bytes;
  final Uint16List attrs;

  int cursorRow = 0;

  /// May equal [cols] after the last column is written; the next [put] wraps.
  int cursorCol = 0;
  int scrollTop = 0;
  int scrollBottom;

  int byteAt(int row, int col) => bytes[row * cols + col];
  int attrAt(int row, int col) => attrs[row * cols + col];

  int get _col => _clamp(cursorCol, 0, cols - 1);

  void _blank(int start, int end) {
    bytes.fillRange(start, end, 0x20);
    attrs.fillRange(start, end, Attr.normal);
  }

  void moveTo(int row, int col) {
    cursorRow = _clamp(row, 0, rows - 1);
    cursorCol = _clamp(col, 0, cols - 1);
  }

  void put(int byte, int attr) {
    if (cursorCol >= cols) {
      cursorCol = 0;
      lineFeed();
    }
    final i = cursorRow * cols + cursorCol;
    bytes[i] = byte;
    attrs[i] = attr;
    cursorCol++;
  }

  void lineFeed() {
    if (cursorRow == scrollBottom) {
      scrollUp(1);
    } else if (cursorRow < rows - 1) {
      cursorRow++;
    }
  }

  void reverseLineFeed() {
    if (cursorRow == scrollTop) {
      scrollDown(1);
    } else if (cursorRow > 0) {
      cursorRow--;
    }
  }

  void setScrollRegion(int top, int bottom) {
    if (top < 0 || bottom >= rows || top >= bottom) {
      scrollTop = 0;
      scrollBottom = rows - 1;
    } else {
      scrollTop = top;
      scrollBottom = bottom;
    }
  }

  void scrollUp(int n, {int? top, int? bottom}) {
    final t = top ?? scrollTop, b = bottom ?? scrollBottom;
    if (t > b) return;
    final count = _clamp(n, 1, b - t + 1);
    final keepEnd = (b + 1 - count) * cols;
    bytes.setRange(t * cols, keepEnd, bytes, (t + count) * cols);
    attrs.setRange(t * cols, keepEnd, attrs, (t + count) * cols);
    _blank(keepEnd, (b + 1) * cols);
  }

  void scrollDown(int n, {int? top, int? bottom}) {
    final t = top ?? scrollTop, b = bottom ?? scrollBottom;
    if (t > b) return;
    final count = _clamp(n, 1, b - t + 1);
    bytes.setRange((t + count) * cols, (b + 1) * cols, bytes, t * cols);
    attrs.setRange((t + count) * cols, (b + 1) * cols, attrs, t * cols);
    _blank(t * cols, (t + count) * cols);
  }

  void insertLines(int n) {
    if (cursorRow < scrollTop || cursorRow > scrollBottom) return;
    scrollDown(n, top: cursorRow);
  }

  void deleteLines(int n) {
    if (cursorRow < scrollTop || cursorRow > scrollBottom) return;
    scrollUp(n, top: cursorRow);
  }

  void insertChars(int n) {
    final from = cursorRow * cols + _col, end = (cursorRow + 1) * cols;
    final count = _clamp(n, 1, end - from);
    bytes.setRange(from + count, end, bytes, from);
    attrs.setRange(from + count, end, attrs, from);
    _blank(from, from + count);
  }

  void deleteChars(int n) {
    final from = cursorRow * cols + _col, end = (cursorRow + 1) * cols;
    final count = _clamp(n, 1, end - from);
    bytes.setRange(from, end - count, bytes, from + count);
    attrs.setRange(from, end - count, attrs, from + count);
    _blank(end - count, end);
  }

  /// 0: cursor to end of line. 1: start of line through cursor. 2: whole line.
  void eraseInLine(int mode) {
    final rowStart = cursorRow * cols;
    switch (mode) {
      case 1:
        _blank(rowStart, rowStart + _col + 1);
      case 2:
        _blank(rowStart, rowStart + cols);
      default:
        _blank(rowStart + _col, rowStart + cols);
    }
  }

  /// 0: cursor to end of screen. 1: start of screen through cursor. 2: all.
  void eraseInDisplay(int mode) {
    final pos = cursorRow * cols + _col;
    switch (mode) {
      case 1:
        _blank(0, pos + 1);
      case 2:
        _blank(0, cols * rows);
      default:
        _blank(pos, cols * rows);
    }
  }
}
