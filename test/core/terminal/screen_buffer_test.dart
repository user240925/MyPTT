import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';

String rowText(ScreenBuffer s, int r) =>
    String.fromCharCodes(s.bytes.sublist(r * s.cols, (r + 1) * s.cols))
        .trimRight();

void write(ScreenBuffer s, String text) {
  for (final c in text.codeUnits) {
    s.put(c, Attr.normal);
  }
}

ScreenBuffer withRows(List<String> rows) {
  final s = ScreenBuffer(cols: 10, rows: 5);
  for (var r = 0; r < rows.length; r++) {
    s.moveTo(r, 0);
    write(s, rows[r]);
  }
  return s;
}

void main() {
  test('starts blank with default attributes', () {
    final s = ScreenBuffer();
    expect(s.cols, 80);
    expect(s.rows, 24);
    expect(s.byteAt(23, 79), 0x20);
    expect(s.attrAt(0, 0), Attr.normal);
    expect(s.scrollBottom, 23);
  });

  test('put writes at the cursor and advances', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.put(0x41, 0x1F);
    expect(s.byteAt(0, 0), 0x41);
    expect(s.attrAt(0, 0), 0x1F);
    expect(s.cursorCol, 1);
  });

  test('put wraps only when the next character arrives', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    write(s, '0123456789');
    expect(s.cursorRow, 0);
    expect(s.cursorCol, 10);
    write(s, 'X');
    expect(rowText(s, 0), '0123456789');
    expect(rowText(s, 1), 'X');
  });

  test('moveTo clamps to the screen', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.moveTo(99, 99);
    expect(s.cursorRow, 4);
    expect(s.cursorCol, 9);
    s.moveTo(-3, -3);
    expect(s.cursorRow, 0);
    expect(s.cursorCol, 0);
  });

  test('lineFeed at the bottom scrolls the screen up', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.moveTo(4, 0);
    s.lineFeed();
    expect(rowText(s, 0), 'R1');
    expect(rowText(s, 3), 'R4');
    expect(rowText(s, 4), '');
    expect(s.cursorRow, 4);
  });

  test('lineFeed respects the scroll region', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.setScrollRegion(1, 3);
    s.moveTo(3, 0);
    s.lineFeed();
    expect(rowText(s, 0), 'R0');
    expect(rowText(s, 1), 'R2');
    expect(rowText(s, 2), 'R3');
    expect(rowText(s, 3), '');
    expect(rowText(s, 4), 'R4');
  });

  test('reverseLineFeed at the top scrolls down', () {
    final s = withRows(['R0', 'R1', 'R2', 'R3', 'R4']);
    s.moveTo(0, 0);
    s.reverseLineFeed();
    expect(rowText(s, 0), '');
    expect(rowText(s, 1), 'R0');
    expect(rowText(s, 4), 'R3');
  });

  test('an invalid scroll region resets to the full screen', () {
    final s = ScreenBuffer(cols: 10, rows: 5);
    s.setScrollRegion(3, 1);
    expect(s.scrollTop, 0);
    expect(s.scrollBottom, 4);
  });

  test('insertLines and deleteLines shift rows below the cursor', () {
    final a = withRows(['R0', 'R1', 'R2']);
    a.moveTo(1, 0);
    a.insertLines(1);
    expect(rowText(a, 1), '');
    expect(rowText(a, 2), 'R1');
    expect(rowText(a, 3), 'R2');

    final b = withRows(['R0', 'R1', 'R2']);
    b.moveTo(1, 0);
    b.deleteLines(1);
    expect(rowText(b, 1), 'R2');
    expect(rowText(b, 2), '');
  });

  test('insertChars and deleteChars shift within the row', () {
    final a = withRows(['ABCDE']);
    a.moveTo(0, 1);
    a.insertChars(2);
    expect(rowText(a, 0), 'A  BCDE');

    final b = withRows(['ABCDE']);
    b.moveTo(0, 1);
    b.deleteChars(2);
    expect(rowText(b, 0), 'ADE');
  });

  test('eraseInLine modes', () {
    final a = withRows(['ABCDE'])..moveTo(0, 2);
    a.eraseInLine(0);
    expect(rowText(a, 0), 'AB');

    final b = withRows(['ABCDE'])..moveTo(0, 2);
    b.eraseInLine(1);
    expect(rowText(b, 0), '   DE');

    final c = withRows(['ABCDE'])..moveTo(0, 2);
    c.eraseInLine(2);
    expect(rowText(c, 0), '');
  });

  test('eraseInDisplay modes', () {
    final a = withRows(['AAAAA', 'BBBBB', 'CCCCC'])..moveTo(1, 2);
    a.eraseInDisplay(0);
    expect(rowText(a, 0), 'AAAAA');
    expect(rowText(a, 1), 'BB');
    expect(rowText(a, 2), '');

    final b = withRows(['AAAAA', 'BBBBB', 'CCCCC'])..moveTo(1, 2);
    b.eraseInDisplay(1);
    expect(rowText(b, 0), '');
    expect(rowText(b, 1), '   BB');
    expect(rowText(b, 2), 'CCCCC');

    final c = withRows(['AAAAA', 'BBBBB'])..moveTo(1, 2);
    c.eraseInDisplay(2);
    expect(rowText(c, 0), '');
    expect(rowText(c, 1), '');
  });

  test('oversized counts are clamped instead of throwing', () {
    final s = withRows(['R0', 'R1', 'R2']);
    s.moveTo(1, 3);
    s.insertLines(999);
    s.deleteLines(999);
    s.insertChars(999);
    s.deleteChars(999);
    s.scrollUp(999);
    s.scrollDown(999);
    expect(rowText(s, 0), '');
  });
}
