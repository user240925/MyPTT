import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/connection/ws_connection.dart';

void main() {
  late HttpServer server;
  late List<WebSocket> serverSockets;
  late List<String?> origins;
  late Completer<void> handshakeGate;
  late int serverSocketsClosed;

  setUp(() async {
    serverSockets = [];
    origins = [];
    serverSocketsClosed = 0;
    handshakeGate = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      origins.add(request.headers.value('origin'));
      await handshakeGate.future;
      final socket = await WebSocketTransformer.upgrade(request);
      serverSockets.add(socket);
      socket.listen(socket.add, onDone: () => serverSocketsClosed++);
    });
  });

  tearDown(() => server.close(force: true));

  WsConnection connectionToServer() =>
      WsConnection(uri: Uri.parse('ws://127.0.0.1:${server.port}/bbs'));

  test('sends the Origin header, exchanges binary data, and reconnects', () async {
    handshakeGate.complete();
    final conn = connectionToServer();

    await conn.connect();
    expect(conn.status, ConnectionStatus.connected);
    expect(origins.single, 'app://pcman');

    final echoed = conn.data.first;
    conn.send([0xA4, 0xA4, 0x1B]);
    expect(await echoed, [0xA4, 0xA4, 0x1B]);

    final dropped = conn.statusChanges
        .firstWhere((s) => s == ConnectionStatus.disconnected);
    await serverSockets.single.close();
    await dropped;
    expect(conn.status, ConnectionStatus.disconnected);

    await conn.connect();
    expect(conn.status, ConnectionStatus.connected);
    await conn.close();
  });

  test('close during connect stays disconnected and closes the late socket',
      () async {
    final conn = connectionToServer();
    final connecting = conn.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(conn.status, ConnectionStatus.connecting);

    await conn.close();
    handshakeGate.complete();
    await connecting;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(conn.status, ConnectionStatus.disconnected);
    expect(serverSockets.length, 1);
    expect(serverSocketsClosed, 1);
  });
}
