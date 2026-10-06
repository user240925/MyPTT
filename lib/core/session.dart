import 'dart:async';

import 'connection/connection.dart';
import 'encoding/big5_codec.dart';
import 'terminal/row_glyphs.dart';
import 'terminal/screen_buffer.dart';
import 'terminal/telnet_filter.dart';
import 'terminal/terminal.dart';

/// Wires a [Connection] to a terminal and exposes the resulting screen.
class TerminalSession {
  TerminalSession(this.connection, this.codec, {int cols = 80, int rows = 24})
      : screen = ScreenBuffer(cols: cols, rows: rows) {
    _terminal = Terminal(screen, onReply: _reply);
    _telnet = TelnetFilter(
      onData: (bytes) {
        _terminal.feed(bytes);
        _updates.add(null);
      },
      onReply: _reply,
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
  final _userActivity = StreamController<void>.broadcast(sync: true);

  ConnectionStatus get status => connection.status;

  /// Fires whenever the screen content or the connection status changes.
  Stream<void> get updates => _updates.stream;

  /// Fires when the user sends something; protocol replies and keep-alives
  /// do not count.
  Stream<void> get userActivity => _userActivity.stream;

  /// Text of the row the cursor is on, without trailing spaces.
  String get cursorRowText => rowString(screen, screen.cursorRow, codec);

  /// Starts a new connection from a blank terminal. Does nothing if a
  /// connection is already open or in progress.
  Future<void> connect() async {
    if (connection.status != ConnectionStatus.disconnected) return;
    _terminal.reset();
    _telnet.reset();
    await connection.connect();
  }

  void _reply(List<int> bytes) => sendBytes(bytes, userInitiated: false);

  void sendBytes(List<int> bytes, {bool userInitiated = true}) {
    if (connection.status != ConnectionStatus.connected) return;
    connection.send(bytes);
    if (userInitiated) _userActivity.add(null);
  }

  /// Returns the number of characters that had no Big5 mapping.
  int sendText(String text) {
    if (connection.status != ConnectionStatus.connected) return 0;
    final encoded = codec.encode(text);
    connection.send(encoded.bytes);
    _userActivity.add(null);
    return encoded.unmappable;
  }

  /// Starts every teardown step immediately, so the connection is closed
  /// even if the caller never awaits the result.
  Future<void> dispose() async {
    await Future.wait([
      _dataSub.cancel(),
      _statusSub.cancel(),
      connection.close(),
      _updates.close(),
      _userActivity.close(),
    ]);
  }
}
