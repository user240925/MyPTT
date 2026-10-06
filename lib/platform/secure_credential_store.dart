import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/login/credentials.dart';

/// Stores the PTT credentials in the platform keychain.
///
/// Keychain behaviour that can only be checked on a real iPhone lives here.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore();

  static const String _userIdKey = 'ptt_user_id';
  static const String _passwordKey = 'ptt_password';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<Credentials?> load() async {
    final userId = await _storage.read(key: _userIdKey);
    final password = await _storage.read(key: _passwordKey);
    if (userId == null || password == null) return null;
    return Credentials(userId, password);
  }

  @override
  Future<void> save(Credentials credentials) async {
    await _storage.write(key: _userIdKey, value: credentials.userId);
    await _storage.write(key: _passwordKey, value: credentials.password);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _passwordKey);
  }
}
