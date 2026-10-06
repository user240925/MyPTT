import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/anti_idle.dart';
import '../core/connection/connection.dart';
import '../core/login/auto_login.dart';
import '../core/login/credentials.dart';
import '../core/session.dart';

/// Owns one [TerminalSession] and decides when to connect, log in, keep the
/// connection alive, and what the page should show when it drops.
///
/// Foreground-return reconnect timing, which can only be checked on a real
/// iPhone, lives in [onResumed].
class SessionController extends ChangeNotifier {
  SessionController(
    this.session, {
    this.credentials,
    this.loginTimeout = const Duration(seconds: 10),
  }) {
    _antiIdle = AntiIdle(session);
    _updates = session.updates.listen((_) => _onUpdate());
  }

  final TerminalSession session;

  /// When set, typed automatically at the login prompts.
  final Credentials? credentials;

  /// How long after connecting auto-login keeps waiting for its prompts.
  final Duration loginTimeout;

  /// How long after returning to the foreground a drop still counts as
  /// having happened in the background.
  static const Duration _resumeGrace = Duration(seconds: 5);

  late final AntiIdle _antiIdle;
  late final StreamSubscription<void> _updates;
  AutoLogin? _autoLogin;
  Timer? _loginTimer;
  Timer? _resumeTimer;
  bool _connecting = false;
  bool _offline = false;
  bool _everConnected = false;
  bool _disposed = false;
  String? _error;
  Object? _lastNotified;

  ConnectionStatus get status => session.status;
  bool get connecting => _connecting;

  /// The user chose to keep looking at the last screen instead of reconnecting.
  bool get offline => _offline;
  bool get everConnected => _everConnected;
  String? get error => _error;

  bool get showDisconnectedOverlay =>
      status == ConnectionStatus.disconnected && !_connecting && !_offline;
  bool get inputEnabled => status == ConnectionStatus.connected;

  Future<void> connect() async {
    if (_disposed || _connecting) return;
    if (status != ConnectionStatus.disconnected) return;
    _connecting = true;
    _offline = false;
    _error = null;
    _stopAutoLogin();
    final credentials = this.credentials;
    if (credentials != null) _autoLogin = AutoLogin(credentials);
    _notifyIfChanged();
    try {
      await session.connect();
    } catch (e) {
      _error = '$e';
      _stopAutoLogin();
    }
    _connecting = false;
    _notifyIfChanged();
  }

  void browseOffline() {
    if (status != ConnectionStatus.disconnected) return;
    _offline = true;
    _notifyIfChanged();
  }

  /// Call when the app returns to the foreground.
  void onResumed() {
    if (_disposed || !_everConnected || _offline) return;
    if (status == ConnectionStatus.disconnected) {
      connect();
      return;
    }
    // The app was frozen in the background, so a connection that died there
    // is often only noticed moments after this call.
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeGrace, () {});
  }

  void _onUpdate() {
    if (_disposed) return;
    if (status == ConnectionStatus.connected) {
      _everConnected = true;
      _antiIdle.start();
      final login = _autoLogin;
      if (login != null && login.active) {
        _loginTimer ??= Timer(loginTimeout, login.giveUp);
        final reply = login.onCursorRow(session.cursorRowText);
        if (reply != null) session.sendText(reply);
      }
    } else if (status == ConnectionStatus.disconnected) {
      _antiIdle.stop();
      _stopAutoLogin();
      if (_resumeTimer?.isActive ?? false) {
        _resumeTimer?.cancel();
        scheduleMicrotask(connect);
      }
    }
    _notifyIfChanged();
  }

  void _stopAutoLogin() {
    _loginTimer?.cancel();
    _loginTimer = null;
    _autoLogin = null;
  }

  /// Screen updates arrive constantly; listeners only care about these.
  void _notifyIfChanged() {
    if (_disposed) return;
    final snapshot = (status, _connecting, _offline, _everConnected, _error);
    if (snapshot == _lastNotified) return;
    _lastNotified = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resumeTimer?.cancel();
    _antiIdle.stop();
    _stopAutoLogin();
    _updates.cancel();
    unawaited(session.dispose());
    super.dispose();
  }
}
