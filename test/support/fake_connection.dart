import 'dart:async';
import 'dart:typed_data';

import 'package:myptt/core/connection/connection.dart';

class FakeConnection implements Connection {
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final _status = StreamController<ConnectionStatus>.broadcast(sync: true);

  /// Everything passed to [send], in order.
  final List<int> sent = [];

  @override
  ConnectionStatus status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get data => _data.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _status.stream;

  @override
  Future<void> connect() async => _set(ConnectionStatus.connected);

  @override
  void send(List<int> bytes) => sent.addAll(bytes);

  @override
  Future<void> close() async => _set(ConnectionStatus.disconnected);

  /// Simulates bytes arriving from the server.
  void emit(List<int> bytes) => _data.add(Uint8List.fromList(bytes));

  /// Simulates the server dropping the connection.
  void drop() => _set(ConnectionStatus.disconnected);

  void _set(ConnectionStatus s) {
    status = s;
    _status.add(s);
  }
}
