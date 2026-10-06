import 'credentials.dart';

enum AutoLoginState { waitingForId, waitingForPassword, done, gaveUp }

/// Types the user id and password when PTT asks for them, once per
/// connection. It only reacts to the row the cursor is on, so text elsewhere
/// on the screen can never trigger it.
class AutoLogin {
  AutoLogin(this._credentials);

  /// Text that identifies the id prompt on the cursor's row.
  static const String _idPrompt = '請輸入代號';

  /// Both must appear on the cursor's row for it to be the password prompt.
  static const List<String> _passwordPrompt = ['請輸入', '密碼'];

  final Credentials _credentials;
  AutoLoginState _state = AutoLoginState.waitingForId;

  AutoLoginState get state => _state;

  bool get active =>
      _state == AutoLoginState.waitingForId ||
      _state == AutoLoginState.waitingForPassword;

  /// Call after each screen update with the text of the cursor's row.
  /// Returns what to type, or null.
  String? onCursorRow(String row) {
    switch (_state) {
      case AutoLoginState.waitingForId:
        if (!row.contains(_idPrompt)) return null;
        _state = AutoLoginState.waitingForPassword;
        return '${_credentials.userId}\r';
      case AutoLoginState.waitingForPassword:
        if (!_passwordPrompt.every(row.contains)) return null;
        _state = AutoLoginState.done;
        return '${_credentials.password}\r';
      case AutoLoginState.done:
      case AutoLoginState.gaveUp:
        return null;
    }
  }

  /// Stops reacting, for example after a timeout. A finished login stays done.
  void giveUp() {
    if (active) _state = AutoLoginState.gaveUp;
  }
}
