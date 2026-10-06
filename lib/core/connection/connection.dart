import 'dart:typed_data';

enum ConnectionStatus { disconnected, connecting, connected }

/// A byte pipe to the BBS. Implementations must be replaceable so the
/// terminal can be tested without a network.
abstract class Connection {
  ConnectionStatus get status;
  Stream<ConnectionStatus> get statusChanges;
  Stream<Uint8List> get data;

  /// Throws if the connection cannot be established; [status] is then
  /// [ConnectionStatus.disconnected].
  Future<void> connect();
  void send(List<int> bytes);
  Future<void> close();
}
