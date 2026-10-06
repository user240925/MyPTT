import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/input_strip.dart';
import 'package:myptt/ui/key_bar.dart';
import 'package:myptt/ui/session_controller.dart';
import 'package:myptt/ui/terminal_page.dart';

import '../support/fake_connection.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late List<String> opened;

  Future<void> pumpPage(WidgetTester tester, {Object? connectError}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    conn = FakeConnection()..connectError = connectError;
    opened = [];
    await tester.pumpWidget(MaterialApp(
      home: TerminalPage(
        controller: SessionController(TerminalSession(conn, codec)),
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
      ),
    ));
    await tester.pump();
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('connects on open and shows the input controls', (tester) async {
    await pumpPage(tester);
    expect(conn.status, ConnectionStatus.connected);
    expect(find.byType(InputStrip), findsOneWidget);
    expect(find.byType(KeyBar), findsOneWidget);
    expect(find.text('已斷線'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('a drop dims the screen and offers reconnect or keep browsing',
      (tester) async {
    await pumpPage(tester);
    conn.emit('last screen https://example.com/x'.codeUnits);
    conn.drop();
    await tester.pump();

    expect(find.text('已斷線'), findsOneWidget);
    expect(find.text('重新連線'), findsOneWidget);
    expect(find.text('繼續瀏覽'), findsOneWidget);
    expect(find.byType(InputStrip), findsNothing);
    expect(find.byType(KeyBar), findsNothing);

    await tester.tap(find.text('繼續瀏覽'));
    await tester.pump();
    expect(find.text('已斷線'), findsNothing);
    expect(find.text('已離線'), findsOneWidget);
    expect(find.byType(InputStrip), findsNothing);

    // Offline: links still open, swipes send nothing.
    final topLeft = tester.getTopLeft(find.byKey(const Key('terminal-zoom')));
    await tester.tapAt(topLeft + const Offset(125, 10));
    expect(opened, ['https://example.com/x']);
    await tester.dragFrom(topLeft + const Offset(400, 200), const Offset(200, 0));
    expect(conn.sent, isEmpty);

    await tester.tap(find.text('重新連線'));
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(find.text('已離線'), findsNothing);
    expect(find.byType(InputStrip), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets('a failed first connection shows the reason and only a retry',
      (tester) async {
    await pumpPage(tester, connectError: const SocketException('no route'));
    expect(find.text('連線失敗'), findsOneWidget);
    expect(find.textContaining('no route'), findsOneWidget);
    expect(find.text('重新連線'), findsOneWidget);
    expect(find.text('繼續瀏覽'), findsNothing);

    conn.connectError = null;
    await tester.tap(find.text('重新連線'));
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(find.text('連線失敗'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('returning to the foreground reconnects after a drop', (tester) async {
    await pumpPage(tester);
    // The framework only accepts the states in the order a real device
    // goes through them.
    void lifecycle(List<AppLifecycleState> states) =>
        states.forEach(tester.binding.handleAppLifecycleStateChanged);

    lifecycle(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    conn.drop();
    lifecycle(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump();
    await tester.pump();
    expect(conn.status, ConnectionStatus.connected);
    expect(conn.connectCalls, 2);
    expect(find.text('已斷線'), findsNothing);
    await disposePage(tester);
  });

  testWidgets('swipes on the page reach the server when connected', (tester) async {
    await pumpPage(tester);
    final topLeft = tester.getTopLeft(find.byKey(const Key('terminal-zoom')));
    await tester.dragFrom(topLeft + const Offset(400, 200), const Offset(200, 0));
    expect(conn.sent, '\x1b[D'.codeUnits);
    await disposePage(tester);
  });

  testWidgets('leaving the page closes the connection', (tester) async {
    await pumpPage(tester);
    await disposePage(tester);
    expect(conn.status, ConnectionStatus.disconnected);
  });
}
