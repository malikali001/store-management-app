/// Manages the database encryption key: a random 256-bit key kept in the OS
/// keystore. It is generated once on first launch and reused thereafter. The
/// key is returned as 64 hex characters, ready for SQLCipher's raw-key syntax
/// (`PRAGMA key = "x'...'"`) which skips SQLCipher's own KDF (correct for an
/// already-random key).
///
/// The key never derives from the PIN, so changing or forgetting the PIN does
/// not lose data. The PIN/biometric lock is the access gate; this key + the
/// keystore is what makes the on-disk database unreadable if the file is stolen.
library;

import 'dart:math';

import 'secure_store.dart';

class DbKey {
  final SecureStore _store;
  DbKey(this._store);

  /// Returns the existing key, or creates and persists a new random one.
  Future<String> getOrCreate() async {
    final existing = await _store.read(SecureStore.kDbKey);
    if (existing != null && existing.length == 64 && _isHex(existing)) {
      return existing;
    }
    final key = _randomHex(32); // 32 bytes = 256 bits
    await _store.write(SecureStore.kDbKey, key);
    return key;
  }

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      sb.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static bool _isHex(String s) =>
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);
}
