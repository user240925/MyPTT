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

  /// Bumped by every connect and close, so a handshake that finishes after
  /// it was abandoned can tell it is stale.
  int _attempt = 0;

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
    final attempt = ++_attempt;
    _set(ConnectionStatus.connecting);
    final handshake = WebSocket.connect(
      uri.toString(),
      headers: {'Origin': origin},
    );
    try {
      final socket = await handshake.timeout(_connectTimeout);
      if (attempt != _attempt) {
        unawaited(socket.close());
        return;
      }
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
    } on TimeoutException {
      // The handshake may still complete later; do not leave that socket open.
      unawaited(handshake.then<void>((s) => s.close(), onError: (Object _) {}));
      if (attempt == _attempt) _set(ConnectionStatus.disconnected);
      rethrow;
    } catch (_) {
      if (attempt == _attempt) _set(ConnectionStatus.disconnected);
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
    _attempt++;
    final socket = _socket;
    _socket = null;
    _set(ConnectionStatus.disconnected);
    await socket?.close();
  }
}
