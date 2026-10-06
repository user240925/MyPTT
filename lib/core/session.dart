import 'dart:async';

import 'connection/connection.dart';
import 'encoding/big5_codec.dart';
import 'terminal/screen_buffer.dart';
import 'terminal/telnet_filter.dart';
import 'terminal/terminal.dart';

/// Wires a [Connection] to a terminal and exposes the resulting screen.
class TerminalSession {
  TerminalSession(this.connection, this.codec, {int cols = 80, int rows = 24})
      : screen = ScreenBuffer(cols: cols, rows: rows) {
    _terminal = Terminal(screen, onReply: sendBytes);
    _telnet = TelnetFilter(
      onData: (bytes) {
        _terminal.feed(bytes);
        _updates.add(null);
      },
      onReply: sendBytes,
      cols: cols,
      rows: rows,
    );
    _dataSub = connection.data.listen(_telnet.feed);
    _statusSub = connection.statusChanges.listen((_) => _updates.add(null));
  }

  final Connection connection;
  final Big5Codec codec;
  final ScreenBuffer screen;

  late final Terminal _terminal;
  late final TelnetFilter _telnet;
  late final StreamSubscription<void> _dataSub;
  late final StreamSubscription<void> _statusSub;
  final _updates = StreamController<void>.broadcast(sync: true);

  ConnectionStatus get status => connection.status;

  /// Fires whenever the screen content or the connection status changes.
  Stream<void> get updates => _updates.stream;

  Future<void> connect() => connection.connect();

  void sendBytes(List<int> bytes) {
    if (connection.status != ConnectionStatus.connected) return;
    connection.send(bytes);
  }

  /// Returns the number of characters that had no Big5 mapping.
  int sendText(String text) {
    if (connection.status != ConnectionStatus.connected) return 0;
    final encoded = codec.encode(text);
    connection.send(encoded.bytes);
    return encoded.unmappable;
  }

  Future<void> dispose() async {
    await _dataSub.cancel();
    await _statusSub.cancel();
    await connection.close();
    await _updates.close();
  }
}
