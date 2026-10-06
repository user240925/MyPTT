import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/key_bar.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late ValueNotifier<bool> ctrl;

  Future<void> pumpBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    ctrl = ValueNotifier(false);
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: KeyBar(session: session, ctrlLatch: ctrl)),
    ));
  }

  Future<void> disposeBar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    ctrl.dispose();
    await tester.runAsync(session.dispose);
  }

  testWidgets('each key sends its bytes', (tester) async {
    await pumpBar(tester);
    const expected = {
      '←': '\x1b[D', '↑': '\x1b[A', '↓': '\x1b[B', '→': '\x1b[C',
      'Enter': '\r', 'PgUp': '\x1b[5~', 'PgDn': '\x1b[6~',
      'Home': '\x1b[1~', 'End': '\x1b[4~', 'Esc': '\x1b', 'Tab': '\t',
    };
    for (final entry in expected.entries) {
      conn.sent.clear();
      await tester.tap(find.text(entry.key));
      expect(conn.sent, entry.value.codeUnits, reason: entry.key);
    }
    await disposeBar(tester);
  });

  testWidgets('Ctrl toggles the latch and sends nothing itself', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Ctrl'));
    expect(ctrl.value, isTrue);
    await tester.tap(find.text('Ctrl'));
    expect(ctrl.value, isFalse);
    expect(conn.sent, isEmpty);
    await disposeBar(tester);
  });

  testWidgets('tapping a key does not take keyboard focus', (tester) async {
    await pumpBar(tester);
    final field = FocusNode();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TextField(focusNode: field, autofocus: true),
          KeyBar(session: session, ctrlLatch: ctrl),
        ]),
      ),
    ));
    await tester.pump();
    expect(field.hasFocus, isTrue);
    await tester.tap(find.text('↑'));
    await tester.pump();
    expect(field.hasFocus, isTrue);
    field.dispose();
    await disposeBar(tester);
  });
}
