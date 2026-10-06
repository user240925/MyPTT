import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'connection.dart';

/// Connects to PTT over WebSocket. PTT rejects the handshake with HTTP 403
/// unless an Origin header is present.
class WsConnection implements Connection {
  WsConnection({Uri? uri, this.origin = 'app://pcman'})
      : uri = uri ?? Uri.parse('wss://ws.ptt.cc/bbs');

  final Uri uri;
  final String origin;

  static const Duration _connectTimeout = Duration(seconds: 15);

  final _data = StreamController<Uint8List>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  WebSocket? _socket;

  @override
  ConnectionStatus status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _status.stream;

  void _set(ConnectionStatus s) {
    if (status == s) return;
    status = s;
    _status.add(s);
  }

  @override
  Future<void> connect() async {
    if (status != ConnectionStatus.disconnected) return;
    _set(ConnectionStatus.connecting);
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        headers: {'Origin': origin},
      ).timeout(_connectTimeout);
      _socket = socket;
      _set(ConnectionStatus.connected);
      socket.listen(
        (message) {
          if (message is List<int>) _data.add(Uint8List.fromList(message));
        },
        onError: (Object _) => _closed(socket),
        onDone: () => _closed(socket),
        cancelOnError: true,
      );
    } catch (_) {
      _set(ConnectionStatus.disconnected);
      rethrow;
    }
  }

  void _closed(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _set(ConnectionStatus.disconnected);
  }

  @override
  void send(List<int> bytes) => _socket?.add(bytes);

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    _set(ConnectionStatus.disconnected);
    await socket?.close();
  }
}
