import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/selection.dart';
import 'package:myptt/core/terminal/terminal.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late ScreenBuffer screen;
  late Terminal term;

  setUp(() {
    screen = ScreenBuffer();
    term = Terminal(screen);
  });

  void feed(String s) => term.feed(codec.encode(s).bytes);

  test('selection orders its ends regardless of drag direction', () {
    const sel = Selection(CellPos(3, 5), CellPos(1, 9));
    expect(sel.start, const CellPos(1, 9));
    expect(sel.end, const CellPos(3, 5));
  });

  test('columnsOnRow covers partial first and last rows', () {
    const sel = Selection(CellPos(1, 9), CellPos(3, 5));
    expect(sel.columnsOnRow(0, 80), isNull);
    expect(sel.columnsOnRow(1, 80), (9, 79));
    expect(sel.columnsOnRow(2, 80), (0, 79));
    expect(sel.columnsOnRow(3, 80), (0, 5));
    expect(sel.columnsOnRow(4, 80), isNull);
  });

  test('text of a single-row range', () {
    feed('Hello World');
    const sel = Selection(CellPos(0, 0), CellPos(0, 4));
    expect(textInRange(screen, codec, sel), 'Hello');
  });

  test('a wide character is included when either half is selected', () {
    feed('A中文B');
    expect(textInRange(screen, codec, const Selection(CellPos(0, 2), CellPos(0, 3))), '中文');
    expect(textInRange(screen, codec, const Selection(CellPos(0, 1), CellPos(0, 1))), '中');
  });

  test('multi-row ranges are joined with newlines and right-trimmed', () {
    feed('first line\r\nsecond\r\nthird line');
    const sel = Selection(CellPos(0, 6), CellPos(2, 4));
    expect(textInRange(screen, codec, sel), 'line\nsecond\nthird');
  });

  test('out-of-range positions are clamped', () {
    feed('abc');
    const sel = Selection(CellPos(-5, -5), CellPos(99, 999));
    expect(textInRange(screen, codec, sel).split('\n').first, 'abc');
  });

  test('urlAt finds the URL under a cell', () {
    feed('see https://www.ptt.cc/bbs/Stock/index.html now');
    expect(urlAt(screen, codec, const CellPos(0, 4)), 'https://www.ptt.cc/bbs/Stock/index.html');
    expect(urlAt(screen, codec, const CellPos(0, 42)), 'https://www.ptt.cc/bbs/Stock/index.html');
    expect(urlAt(screen, codec, const CellPos(0, 0)), isNull);
    expect(urlAt(screen, codec, const CellPos(0, 44)), isNull);
    expect(urlAt(screen, codec, const CellPos(5, 0)), isNull);
  });

  test('urlSpansOfRow lists every URL with its columns', () {
    feed('a http://x.io/1 中 https://y.io/2. end');
    final spans = urlSpansOfRow(screen, codec, 0);
    expect(spans.length, 2);
    expect(spans[0].url, 'http://x.io/1');
    expect((spans[0].firstCol, spans[0].lastCol), (2, 14));
    expect(spans[1].url, 'https://y.io/2');
    expect((spans[1].firstCol, spans[1].lastCol), (19, 32));
    expect(urlSpansOfRow(screen, codec, 1), isEmpty);
    expect(urlSpansOfRow(screen, codec, -1), isEmpty);
    expect(urlSpansOfRow(screen, codec, 99), isEmpty);
  });

  test('urlAt accounts for wide characters before the URL', () {
    feed('網址 http://example.com/a 結束');
    expect(urlAt(screen, codec, const CellPos(0, 5)), 'http://example.com/a');
    expect(urlAt(screen, codec, const CellPos(0, 3)), isNull);
  });

  test('urlAt drops trailing punctuation and stops at non-ASCII', () {
    feed('(https://example.com/x).');
    expect(urlAt(screen, codec, const CellPos(0, 5)), 'https://example.com/x');
    screen.moveTo(1, 0);
    feed('https://example.com/y，後面');
    expect(urlAt(screen, codec, const CellPos(1, 3)), 'https://example.com/y');
  });
}
