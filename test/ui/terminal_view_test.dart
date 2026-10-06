import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/terminal_view.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;

  Future<void> pumpView(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    await session.connect();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(session: session))),
    );
  }

  Future<void> disposeView(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Stream teardown completes on the real event loop, not the test's fake one.
    await tester.runAsync(session.dispose);
  }

  testWidgets('paints every kind of glyph without throwing', (tester) async {
    await pumpView(tester);
    // Text, a two-colour wide char, blink, inverse, and a lone lead byte.
    conn.emit([
      ...'\x1b[1;33;44mPTT \x1b[m'.codeUnits,
      ...codec.encode('批踢踢 █▄▌◢◣◤◥─│┌┐└┘├┤┬┴┼').bytes,
      ...'\x1b[31m'.codeUnits, 0xA4, ...'\x1b[32m'.codeUnits, 0xA4,
      ...'\x1b[5mblink\x1b[0;7minverse\x1b[m'.codeUnits,
      0xA4, 0x31,
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);

    // Advance past one blink interval so both blink phases get painted.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await disposeView(tester);
  });

  testWidgets('hardware keys are sent to the server', (tester) async {
    await pumpView(tester);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(conn.sent, [...'\x1b[A'.codeUnits, 0x0D, ...'\x1b[6~'.codeUnits]);

    conn.sent.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    expect(conn.sent, [0x61]);

    conn.sent.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(conn.sent, [0x10]);
    await disposeView(tester);
  });

  testWidgets('survives very small and very large sizes', (tester) async {
    await pumpView(tester);
    conn.emit(codec.encode('中文 ABC █').bytes);
    for (final size in const [Size(1, 1), Size(40, 20), Size(4000, 3000)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await disposeView(tester);
  });
}
