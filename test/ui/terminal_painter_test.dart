import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';
import 'package:myptt/core/terminal/selection.dart';
import 'package:myptt/core/terminal/terminal.dart';
import 'package:myptt/ui/terminal_painter.dart';

import '../support/paint_pixels.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  // 80x24 cells of 10x20 pixels.
  const size = Size(800, 480);
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);

  TerminalPainter painter(
    ScreenBuffer screen, {
    bool blinkOn = true,
    bool showCursor = false,
    Selection? selection,
  }) =>
      TerminalPainter(
        screen: screen,
        codec: codec,
        blinkOn: blinkOn,
        showCursor: showCursor,
        selection: selection,
      );

  testWidgets('background colour fills the cell', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed('\x1b[44m \x1b[m'.codeUnits);
    final inCell = await paintAndReadPixel(tester, painter(screen), size, const Offset(5, 10));
    final outside = await paintAndReadPixel(tester, painter(screen), size, const Offset(25, 10));
    expect(inCell, const Color(0xFF000080));
    expect(outside, black);
  });

  testWidgets('the cursor is drawn at the cursor cell when enabled', (tester) async {
    final screen = ScreenBuffer()..moveTo(2, 5);
    const inCursor = Offset(55, 2 * 20 + 19);
    expect(await paintAndReadPixel(tester, painter(screen, showCursor: true), size, inCursor), white);
    expect(await paintAndReadPixel(tester, painter(screen), size, inCursor), black);
    expect(
      await paintAndReadPixel(tester, painter(screen, showCursor: true, blinkOn: false), size, inCursor),
      black,
    );
  });

  testWidgets('a cursor past the last column is drawn in the last column', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed(List.filled(80, 0x20));
    expect(screen.cursorCol, 80);
    final c = await paintAndReadPixel(tester, painter(screen, showCursor: true), size, const Offset(795, 19));
    expect(c, white);
  });

  testWidgets('selected cells are tinted', (tester) async {
    final screen = ScreenBuffer();
    const sel = Selection(CellPos(1, 2), CellPos(1, 4));
    final p = painter(screen, selection: sel);
    expect(await paintAndReadPixel(tester, p, size, const Offset(35, 30)), isNot(black));
    expect(await paintAndReadPixel(tester, p, size, const Offset(55, 30)), black);
    expect(await paintAndReadPixel(tester, p, size, const Offset(35, 10)), black);
  });

  testWidgets('a full block fills its whole cell with no gap', (tester) async {
    final screen = ScreenBuffer();
    Terminal(screen).feed([...'\x1b[1;37m'.codeUnits, ...codec.encode('██').bytes]);
    final p = painter(screen);
    for (final x in const [0.0, 19.0, 20.0, 39.0]) {
      expect(await paintAndReadPixel(tester, p, size, Offset(x, 0)), white, reason: 'x=$x top');
      expect(await paintAndReadPixel(tester, p, size, Offset(x, 19)), white, reason: 'x=$x bottom');
    }
  });

  testWidgets('glyphs never paint outside their own cell', (tester) async {
    final screen = ScreenBuffer();
    // A wide Latin letter in column 1; columns 0 and 2 must stay black.
    Terminal(screen).feed(' W '.codeUnits);
    final p = painter(screen);
    for (var y = 0.0; y < 20; y += 3) {
      expect(await paintAndReadPixel(tester, p, size, Offset(8, y)), black, reason: 'left y=$y');
      expect(await paintAndReadPixel(tester, p, size, Offset(21, y)), black, reason: 'right y=$y');
    }
  });
}
