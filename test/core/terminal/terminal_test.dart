import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/terminal.dart';

const esc = '\x1b';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late ScreenBuffer screen;
  late Terminal term;
  late List<int> replies;

  setUp(() {
    screen = ScreenBuffer();
    replies = [];
    term = Terminal(screen, onReply: replies.addAll);
  });

  void feed(String s) => term.feed(s.codeUnits);
  String row(int r) => rowString(screen, r, codec);

  test('plain text with CR LF', () {
    feed('Hello\r\nWorld');
    expect(row(0), 'Hello');
    expect(row(1), 'World');
    expect(screen.cursorRow, 1);
    expect(screen.cursorCol, 5);
  });

  test('backspace and tab', () {
    feed('AB\bC\tD');
    expect(row(0), 'AC      D');
  });

  test('cursor positioning is one-based', () {
    feed('$esc[5;10HX');
    expect(screen.byteAt(4, 9), 0x58);
    feed('$esc[HY');
    expect(screen.byteAt(0, 0), 0x59);
  });

  test('relative cursor movement defaults to one', () {
    feed('$esc[10;10H$esc[A$esc[2B$esc[C$esc[3D');
    expect(screen.cursorRow, 10);
    expect(screen.cursorCol, 7);
  });

  test('SGR sets and resets attributes', () {
    feed('$esc[1;33;44mA$esc[mB$esc[5;7mC');
    final a = screen.attrAt(0, 0);
    expect(Attr.fg(a), 3);
    expect(Attr.bg(a), 4);
    expect(a & Attr.bright, isNot(0));
    expect(screen.attrAt(0, 1), Attr.normal);
    final c = screen.attrAt(0, 2);
    expect(c & Attr.blink, isNot(0));
    expect(c & Attr.inverse, isNot(0));
  });

  test('erase line and erase display', () {
    feed('ABCDE$esc[1;3H$esc[K');
    expect(row(0), 'AB');
    feed('$esc[2;1HXYZ$esc[2J');
    expect(row(0), '');
    expect(row(1), '');
  });

  test('text wraps at column 80', () {
    feed('A' * 80);
    expect(screen.cursorRow, 0);
    feed('B');
    expect(row(0), 'A' * 80);
    expect(row(1), 'B');
  });

  test('line feed on the last row scrolls', () {
    feed([for (var i = 0; i < 25; i++) 'L$i'].join('\r\n'));
    expect(row(0), 'L1');
    expect(row(23), 'L24');
  });

  test('scroll region limits scrolling', () {
    feed('R0\r\nR1\r\nR2\r\nR3\r\nR4');
    feed('$esc[2;4r');
    expect(screen.cursorRow, 0);
    feed('$esc[4;1H\n');
    expect(row(0), 'R0');
    expect(row(1), 'R2');
    expect(row(2), 'R3');
    expect(row(3), '');
    expect(row(4), 'R4');
  });

  test('insert and delete lines', () {
    feed('R0\r\nR1\r\nR2$esc[2;1H$esc[L');
    expect(row(1), '');
    expect(row(2), 'R1');
    expect(row(3), 'R2');
    feed('$esc[M');
    expect(row(1), 'R1');
    expect(row(2), 'R2');
  });

  test('insert and delete characters', () {
    feed('ABCDE$esc[1;2H$esc[2@');
    expect(row(0), 'A  BCDE');
    feed('$esc[2P');
    expect(row(0), 'ABCDE');
  });

  test('save and restore cursor and attributes', () {
    feed('$esc[3;4H$esc[31m${esc}7$esc[10;10H$esc[m${esc}8X');
    expect(screen.byteAt(2, 3), 0x58);
    expect(Attr.fg(screen.attrAt(2, 3)), 1);
    feed('$esc[5;6H$esc[s$esc[H$esc[uY');
    expect(screen.byteAt(4, 5), 0x59);
  });

  test('ESC D and ESC M move down and up', () {
    feed('$esc[3;1H${esc}D');
    expect(screen.cursorRow, 3);
    feed('${esc}M${esc}M');
    expect(screen.cursorRow, 1);
  });

  test('device status report replies with the cursor position', () {
    feed('$esc[3;7H$esc[6n');
    expect(String.fromCharCodes(replies), '$esc[3;7R');
  });

  test('decodes Big5 text into glyphs', () {
    term.feed([0x41, 0xA4, 0xA4, 0xA4, 0xE5, 0x42]);
    expect(row(0), 'A中文B');
    final g = glyphsOfRow(screen, 0, codec);
    expect(g[0].width, 1);
    expect(g[1].col, 1);
    expect(g[1].width, 2);
    expect(g[1].codePoint, 0x4E2D);
    expect(g[2].col, 3);
    expect(g[3].col, 5);
    expect(g.length, 78);
  });

  test('a colour change between the two bytes makes a two-colour glyph', () {
    term.feed([...'$esc[31m'.codeUnits, 0xA4, ...'$esc[32m'.codeUnits, 0xA4]);
    final g = glyphsOfRow(screen, 0, codec).first;
    expect(g.codePoint, 0x4E2D);
    expect(Attr.fg(g.leftAttr), 1);
    expect(Attr.fg(g.rightAttr), 2);
  });

  // Review Focus 1
  test('wide char split across feeds', () {
    term.feed([0xA4]);
    term.feed([0xA4]);
    expect(row(0), '中');
  });

  // Review Focus 2
  test('escape sequence split across feeds', () {
    feed(esc);
    feed('[1;3');
    feed('1mA');
    final a = screen.attrAt(0, 0);
    expect(Attr.fg(a), 1);
    expect(a & Attr.bright, isNot(0));
    expect(row(0), 'A');
  });

  // Review Focus 3
  test('out-of-range cursor is clamped', () {
    feed('$esc[99;999HX');
    expect(screen.byteAt(23, 79), 0x58);
    feed('$esc[0;0HY');
    expect(screen.byteAt(0, 0), 0x59);
    feed('$esc[999A$esc[999D$esc[999B$esc[999C');
    expect(screen.cursorRow, 23);
    expect(screen.cursorCol, 79);
  });

  // Review Focus 4
  test('lone lead byte', () {
    term.feed([0xA4, 0x31, 0x32]);
    final g = glyphsOfRow(screen, 0, codec);
    expect(g[0].codePoint, Big5Codec.replacement);
    expect(g[0].width, 1);
    expect(g[1].codePoint, 0x31);
    expect(g[2].codePoint, 0x32);

    feed('$esc[2;80H');
    term.feed([0xA4]);
    final last = glyphsOfRow(screen, 1, codec).last;
    expect(last.col, 79);
    expect(last.width, 1);
    expect(last.codePoint, Big5Codec.replacement);
  });

  test('lead byte followed by a high byte that is not a trail byte', () {
    term.feed([0xA4, 0x81, 0x41]);
    final g = glyphsOfRow(screen, 0, codec);
    expect(g[0].codePoint, Big5Codec.replacement);
    expect(g[0].width, 1);
    expect(g[1].codePoint, 0x4E22);
    expect(g[1].width, 2);
  });

  test('a Big5 byte that interrupts a control sequence is kept', () {
    term.feed([0x1B, 0x5B, 0x31, 0x3B, 0xA4, 0xA4, 0xA4, 0xE5]);
    expect(row(0), '中文');
  });

  // Review Focus 5
  test('garbage CSI is ignored', () {
    feed('$esc[${'9' * 500};${';' * 200}zA');
    feed('$esc[?25lB');
    feed('$esc[>0cC');
    feed('$esc$esc[1mD');
    feed('$esc#E');
    expect(row(0), 'ABCDE');
  });
}
