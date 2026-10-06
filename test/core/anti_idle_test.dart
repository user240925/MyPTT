import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/anti_idle.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  const interval = Duration(seconds: 60);
  late FakeConnection conn;
  late TerminalSession session;
  late AntiIdle idle;

  Future<void> start(WidgetTester tester) async {
    conn = FakeConnection();
    session = TerminalSession(conn, codec);
    await session.connect();
    idle = AntiIdle(session, interval: interval)..start();
  }

  Future<void> finish(WidgetTester tester) async {
    idle.stop();
    await tester.runAsync(session.dispose);
  }

  test('the keep-alive is ESC O A ESC O B and the default interval is 3 minutes', () {
    expect(AntiIdle.keepAlive, [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42]);
    expect(AntiIdle.defaultInterval, const Duration(minutes: 3));
  });

  testWidgets('sends a keep-alive after each idle interval', (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 59));
    expect(conn.sent, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(conn.sent, AntiIdle.keepAlive);
    await tester.pump(interval);
    expect(conn.sent, [...AntiIdle.keepAlive, ...AntiIdle.keepAlive]);
    await finish(tester);
  });

  testWidgets('user input restarts the countdown', (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 50));
    session.sendBytes([0x41]);
    await tester.pump(const Duration(seconds: 50));
    expect(conn.sent, [0x41]);
    await tester.pump(const Duration(seconds: 11));
    expect(conn.sent, [0x41, ...AntiIdle.keepAlive]);
    await finish(tester);
  });

  testWidgets('nothing is sent while disconnected or after stop', (tester) async {
    await start(tester);
    conn.drop();
    await tester.pump(interval * 2);
    expect(conn.sent, isEmpty);

    await session.connect();
    idle.stop();
    await tester.pump(interval * 2);
    expect(conn.sent, isEmpty);
    await finish(tester);
  });

  testWidgets('start is idempotent', (tester) async {
    await start(tester);
    idle.start();
    idle.start();
    await tester.pump(const Duration(seconds: 61));
    expect(conn.sent, AntiIdle.keepAlive);
    await finish(tester);
  });
}
