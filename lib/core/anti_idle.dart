import 'dart:async';

import 'session.dart';

/// Sends a harmless key sequence when the user has been idle, so the BBS
/// does not drop the connection.
class AntiIdle {
  AntiIdle(this.session, {this.interval = defaultInterval});

  static const Duration defaultInterval = Duration(minutes: 3);

  /// Up then down in application cursor mode; the same default PCMan uses.
  static const List<int> keepAlive = [0x1B, 0x4F, 0x41, 0x1B, 0x4F, 0x42];

  final TerminalSession session;
  final Duration interval;

  StreamSubscription<void>? _activity;
  Timer? _timer;

  /// Safe to call repeatedly.
  void start() {
    if (_activity != null) return;
    _activity = session.userActivity.listen((_) => _restart());
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(
      interval,
      (_) => session.sendBytes(keepAlive, userInitiated: false),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _activity?.cancel();
    _activity = null;
  }
}
