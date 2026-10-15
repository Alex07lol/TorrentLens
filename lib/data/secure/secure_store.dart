import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for sensitive values (provider tokens, API keys).
///
/// The real implementation is backed by the Android Keystore via
/// `flutter_secure_storage`. Secrets are never written to the SQLite database
/// and never logged.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

class KeystoreSecureStore implements SecureStore {
  final FlutterSecureStorage _storage;
  KeystoreSecureStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              // v11 defaults on Android are Keystore-backed AES-GCM with RSA
              // key wrapping, which is exactly what we want for tokens.
              aOptions: AndroidOptions(),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// In-memory store for tests and for the rare case where the Keystore is
/// unavailable — deliberately *not* used to persist secrets to disk.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<Map<String, String>> readAll() async => Map.of(_values);
}

/// Well-known secure-storage keys (centralised so they are easy to audit).
class SecureKeys {
  static const githubToken = 'github.token';
  static String supabaseAnonKey(String providerId) => 'cloud.$providerId.anon_key';
  static String cloudAccessToken(String providerId) => 'cloud.$providerId.access_token';
}
