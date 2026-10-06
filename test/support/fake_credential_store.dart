import 'package:myptt/core/login/credentials.dart';

class FakeCredentialStore implements CredentialStore {
  FakeCredentialStore([this.saved]);

  /// What the store currently holds.
  Credentials? saved;

  /// Number of times [clear] was called.
  int clears = 0;

  /// When set, [load] or [save] throws it.
  Object? loadError;
  Object? saveError;

  @override
  Future<Credentials?> load() async {
    final error = loadError;
    if (error != null) throw error;
    return saved;
  }

  @override
  Future<void> save(Credentials credentials) async {
    final error = saveError;
    if (error != null) throw error;
    saved = credentials;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}
