import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/anti_idle.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/login/credentials.dart';
import 'package:myptt/core/session.dart';
import 'package:myptt/ui/session_controller.dart';

import '../support/fake_connection.dart';

const idPrompt = '請輸入代號，或以 guest 參觀，或以 new 註冊: ';
const passwordPrompt = '請輸入您的密碼: ';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeConnection conn;
  late SessionController controller;

  void create({Credentials? credentials}) {
    conn = FakeConnection();
    controller = SessionController(
      TerminalSession(conn, codec),
      credentials: credentials,
    );
  }

  void show(String text) => conn.emit(codec.encode('\x1b[2J\x1b[H$text').bytes);
  String sentText() => String.fromCharCodes(conn.sent);

  testWidgets('connecting, connected, and dropped states', (tester) async {
    create();
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.everConnected, isFalse);

    final connecting = controller.connect();
    expect(controller.connecting, isTrue);
    expect(controller.showDisconnectedOverlay, isFalse);
    expect(controller.inputEnabled, isFalse);
    await connecting;
    expect(controller.status, ConnectionStatus.connected);
    expect(controller.inputEnabled, isTrue);
    expect(controller.everConnected, isTrue);

    conn.drop();
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.inputEnabled, isFalse);
    expect(controller.error, isNull);
    controller.dispose();
  });

  testWidgets('a failed connection reports the error', (tester) async {
    create();
    conn.connectError = const SocketException('no route');
    await controller.connect();
    expect(controller.status, ConnectionStatus.disconnected);
    expect(controller.error, contains('no route'));
    expect(controller.showDisconnectedOverlay, isTrue);
    expect(controller.everConnected, isFalse);

    conn.connectError = null;
    await controller.connect();
    expect(controller.error, isNull);
    expect(controller.status, ConnectionStatus.connected);
    controller.dispose();
  });

  testWidgets('auto-login types the id and password at their prompts', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show('歡迎');
    expect(conn.sent, isEmpty);
    show(idPrompt);
    expect(sentText(), 'alice\r');
    show(passwordPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    show(idPrompt);
    show(passwordPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    controller.dispose();
  });

  testWidgets('without credentials nothing is typed', (tester) async {
    create();
    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    expect(conn.sent, isEmpty);
    controller.dispose();
  });

  testWidgets('auto-login gives up after the timeout', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show(idPrompt);
    expect(sentText(), 'alice\r');
    await tester.pump(const Duration(seconds: 11));
    show(passwordPrompt);
    expect(sentText(), 'alice\r');
    controller.dispose();
  });

  testWidgets('reconnecting logs in again exactly once', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    conn.drop();
    conn.sent.clear();

    await controller.connect();
    show(idPrompt);
    show(passwordPrompt);
    show(idPrompt);
    expect(sentText(), 'alice\rs3cret\r');
    controller.dispose();
  });

  testWidgets('choosing offline hides the overlay and stays disconnected',
      (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.browseOffline();
    expect(controller.offline, isTrue);
    expect(controller.showDisconnectedOverlay, isFalse);
    expect(controller.inputEnabled, isFalse);

    await controller.connect();
    expect(controller.offline, isFalse);
    expect(controller.inputEnabled, isTrue);
    controller.dispose();
  });

  testWidgets('resuming after a drop reconnects', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.onResumed();
    await tester.pump();
    expect(controller.status, ConnectionStatus.connected);
    expect(conn.connectCalls, 2);
    controller.dispose();
  });

  // Review Focus 4
  testWidgets('resuming repeatedly connects once', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.onResumed();
    controller.onResumed();
    controller.onResumed();
    await tester.pump();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 2);
    expect(controller.status, ConnectionStatus.connected);
    controller.dispose();
  });

  // Review Focus 4
  testWidgets('resuming in offline mode does not reconnect', (tester) async {
    create();
    await controller.connect();
    conn.drop();
    controller.browseOffline();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 1);
    expect(controller.status, ConnectionStatus.disconnected);
    controller.dispose();
  });

  testWidgets('resuming before any successful connection does not connect',
      (tester) async {
    create();
    conn.connectError = const SocketException('down');
    await controller.connect();
    controller.onResumed();
    await tester.pump();
    expect(conn.connectCalls, 1);
    controller.dispose();
  });

  testWidgets('anti-idle runs only while connected', (tester) async {
    create();
    await controller.connect();
    await tester.pump(AntiIdle.defaultInterval + const Duration(seconds: 1));
    expect(conn.sent, AntiIdle.keepAlive);
    conn.drop();
    conn.sent.clear();
    await tester.pump(AntiIdle.defaultInterval * 2);
    expect(conn.sent, isEmpty);
    controller.dispose();
  });

  testWidgets('listeners are told about state changes, not every screen update',
      (tester) async {
    create();
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.connect();
    final afterConnect = notifications;
    show('a');
    show('b');
    show('c');
    expect(notifications, afterConnect);
    conn.drop();
    expect(notifications, afterConnect + 1);
    controller.dispose();
  });

  testWidgets('nothing happens after dispose', (tester) async {
    create(credentials: const Credentials('alice', 's3cret'));
    await controller.connect();
    controller.dispose();
    controller.onResumed();
    await tester.pump(AntiIdle.defaultInterval * 2);
    expect(conn.sent, isEmpty);
  });
}
