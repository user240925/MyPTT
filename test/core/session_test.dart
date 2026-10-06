import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/recognition/screen_recognizer.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/core/terminal/row_glyphs.dart';
import 'package:myptt/core/terminal/screen_buffer.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late TerminalSession session;

  setUp(() {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
  });

  tearDown(() => session.dispose());

  test('incoming bytes reach the screen and fire an update', () async {
    var updates = 0;
    session.updates.listen((_) => updates++);
    await session.connect();
    final before = updates;
    conn.emit([0x48, 0x69, 0xA4, 0xA4]);
    expect(rowString(session.screen, 0, codec), 'Hi中');
    expect(updates, before + 1);
  });

  test('status follows the connection and fires an update', () async {
    var updates = 0;
    session.updates.listen((_) => updates++);
    expect(session.status, ConnectionStatus.disconnected);
    await session.connect();
    expect(session.status, ConnectionStatus.connected);
    conn.drop();
    expect(session.status, ConnectionStatus.disconnected);
    expect(updates, 3);
  });

  test('telnet negotiation is answered through the connection', () async {
    await session.connect();
    conn.emit([255, 253, 31]);
    expect(conn.sent, [255, 251, 31, 255, 250, 31, 0, 80, 0, 24, 255, 240]);
  });

  test('cursor position report is answered through the connection', () async {
    await session.connect();
    conn.emit('\x1b[2;3H\x1b[6n'.codeUnits);
    expect(String.fromCharCodes(conn.sent), '\x1b[2;3R');
  });

  test('sendText encodes to Big5 and reports unmappable characters', () async {
    await session.connect();
    expect(session.sendText('a中'), 0);
    expect(conn.sent, [0x61, 0xA4, 0xA4]);
    conn.sent.clear();
    expect(session.sendText('😀'), 1);
    expect(conn.sent, [0x3F]);
  });

  test('sending while disconnected is dropped without throwing', () {
    session.sendBytes([0x41]);
    expect(session.sendText('中'), 0);
    expect(conn.sent, isEmpty);
  });

  test('the screen keeps its content after a disconnect', () async {
    await session.connect();
    conn.emit('still here'.codeUnits);
    conn.drop();
    expect(rowString(session.screen, 0, codec), 'still here');
  });

  test('reconnecting starts from a clean terminal state', () async {
    await session.connect();
    // Leaves a scroll region, a colour, and an unfinished Telnet subnegotiation.
    conn.emit([...'[5;10r[1;31mold'.codeUnits, 255, 250, 24]);
    conn.drop();

    await session.connect();
    conn.emit('Welcome'.codeUnits);
    expect(rowString(session.screen, 0, codec), 'Welcome');
    expect(session.screen.attrAt(0, 0), Attr.normal);
    expect(session.screen.scrollTop, 0);
    expect(session.screen.scrollBottom, 23);
  });

  test('user sends fire userActivity; automatic replies do not', () async {
    var activity = 0;
    session.userActivity.listen((_) => activity++);
    await session.connect();
    conn.emit([255, 253, 31]);
    conn.emit('\x1b[6n'.codeUnits);
    expect(activity, 0);
    session.sendBytes([0x41]);
    session.sendText('中');
    expect(activity, 2);
    session.sendBytes([0x42], userInitiated: false);
    expect(activity, 2);
    expect(conn.sent.last, 0x42);
  });

  test('cursorRowText is the text of the row the cursor is on', () async {
    await session.connect();
    conn.emit(codec.encode('first\r\n請輸入代號: ').bytes);
    expect(session.cursorRowText, '請輸入代號:');
  });

  test('the placeholder recogniser reports unknown', () {
    expect(NullScreenRecognizer().recognize(session.screen), ScreenKind.unknown);
  });
}
