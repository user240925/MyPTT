import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/input_strip.dart';

import '../support/fake_connection.dart';

const sentinel = '\u200B';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;
  late FocusNode focus;
  late ValueNotifier<bool> ctrl;

  Future<void> pumpStrip(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    focus = FocusNode();
    ctrl = ValueNotifier(false);
    await session.connect();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InputStrip(session: session, focusNode: focus, ctrlLatch: ctrl),
      ),
    ));
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
  }

  Future<void> disposeStrip(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    ctrl.dispose();
    await tester.runAsync(session.dispose);
  }

  TextEditingValue value(String text, {TextRange composing = TextRange.empty}) =>
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: composing,
      );

  testWidgets('committed text is sent immediately as Big5', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('${sentinel}a'));
    expect(conn.sent, [0x61]);
    conn.sent.clear();
    tester.testTextInput.updateEditingValue(value('$sentinel中文'));
    expect(conn.sent, [0xA4, 0xA4, 0xA4, 0xE5]);
    await disposeStrip(tester);
  });

  testWidgets('nothing is sent while the IME is composing', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(
      value('$sentinelㄓㄨ', composing: const TextRange(start: 1, end: 3)),
    );
    expect(conn.sent, isEmpty);
    tester.testTextInput.updateEditingValue(value('$sentinel中'));
    expect(conn.sent, [0xA4, 0xA4]);
    await disposeStrip(tester);
  });

  // Review Focus 3
  testWidgets('keys pressed while composing are left to the IME', (tester) async {
    await pumpStrip(tester);
    // Without a real IME the framework itself edits the field on some of
    // these keys, so the composing state is re-established before each one.
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      tester.testTextInput.updateEditingValue(
        value('$sentinelㄓㄨ', composing: const TextRange(start: 1, end: 3)),
      );
      await tester.sendKeyEvent(key);
      expect(conn.sent, isEmpty, reason: key.keyLabel);
    }
    await disposeStrip(tester);
  });

  testWidgets('deleting the placeholder sends Backspace', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value(''));
    expect(conn.sent, [0x08]);
    tester.testTextInput.updateEditingValue(value(''));
    expect(conn.sent, [0x08, 0x08]);
    await disposeStrip(tester);
  });

  testWidgets('the keyboard action key sends Enter and keeps focus', (tester) async {
    await pumpStrip(tester);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(conn.sent, [0x0D]);
    expect(focus.hasFocus, isTrue);
    await disposeStrip(tester);
  });

  testWidgets('hardware special keys are sent once each', (tester) async {
    await pumpStrip(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(conn.sent, [...'\x1b[A'.codeUnits, 0x0D, 0x08, ...'\x1b[6~'.codeUnits]);

    conn.sent.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(conn.sent, [0x10]);
    await disposeStrip(tester);
  });

  testWidgets('Ctrl latch applies to the next letter only', (tester) async {
    await pumpStrip(tester);
    ctrl.value = true;
    tester.testTextInput.updateEditingValue(value('${sentinel}x'));
    expect(conn.sent, [0x18]);
    expect(ctrl.value, isFalse);
    tester.testTextInput.updateEditingValue(value('${sentinel}x'));
    expect(conn.sent, [0x18, 0x78]);
    await disposeStrip(tester);
  });

  testWidgets('Ctrl latch is released by text that is not a single letter',
      (tester) async {
    await pumpStrip(tester);
    ctrl.value = true;
    tester.testTextInput.updateEditingValue(value('$sentinel中'));
    expect(conn.sent, [0xA4, 0xA4]);
    expect(ctrl.value, isFalse);
    await disposeStrip(tester);
  });

  testWidgets('unsupported characters wait for confirmation', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('${sentinel}a😀b😀'));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(find.text('有 2 個字 PTT 不支援，將以 ? 取代'), findsOneWidget);

    await tester.tap(find.text('送出'));
    await tester.pump();
    expect(conn.sent, [0x61, 0x3F, 0x62, 0x3F]);
    expect(find.textContaining('PTT 不支援'), findsNothing);
    await disposeStrip(tester);
  });

  testWidgets('cancelling unsupported text sends nothing', (tester) async {
    await pumpStrip(tester);
    tester.testTextInput.updateEditingValue(value('$sentinel😀'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(conn.sent, isEmpty);
    expect(find.textContaining('PTT 不支援'), findsNothing);
    await disposeStrip(tester);
  });
}
