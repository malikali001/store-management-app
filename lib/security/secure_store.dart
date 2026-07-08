/// Thin wrapper over the OS-backed secure store (Android Keystore / iOS
/// Keychain) via flutter_secure_storage. Holds the small amount of auth
/// material that must survive independently of the (encrypted) database:
/// the PIN hash, lock settings, failure counters, and the database key.
///
/// Everything here is small strings; never put ledger data here.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  final FlutterSecureStorage _s;

  SecureStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  // Keys.
  static const kPinHash = 'lock_pin_hash';
  static const kLockEnabled = 'lock_enabled';
  static const kBiometricEnabled = 'lock_biometric';
  static const kFailedAttempts = 'lock_failed_attempts';
  static const kLastFailureMs = 'lock_last_failure_ms';
  static const kAutoLockMinutes = 'lock_auto_minutes';
  static const kDbKey = 'db_key';

  /// Reads a value, returning null if the secure store is unavailable (e.g. no
  /// keystore on this platform, or the plugin is absent under `flutter test`).
  /// Reads drive "is the lock on?" checks, so failing to null = lock treated as
  /// off rather than bricking the app.
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  Future<void> delete(String key) => _s.delete(key: key);
}
