class Credentials {
  const Credentials(this.userId, this.password);

  final String userId;
  final String password;
}

/// Where saved credentials live. The real implementation uses the platform
/// keychain; nothing else may persist a password.
abstract class CredentialStore {
  Future<Credentials?> load();
  Future<void> save(Credentials credentials);
  Future<void> clear();
}

final RegExp _userId = RegExp(r'^[A-Za-z0-9]{1,12}$');

/// PTT ids are 1 to 12 letters or digits. Rejecting anything else also keeps
/// control characters out of what auto-login types.
bool isValidUserId(String id) => _userId.hasMatch(id);
