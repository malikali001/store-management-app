/// PIN hashing — pure Dart, no Flutter, no plugins. Unit-tested.
///
/// A PIN is never stored in plaintext. We store a PBKDF2-HMAC-SHA256 derivation
/// with a random per-PIN salt, in the format:
///
///   `pbkdf2_sha256$<iterations>$<saltBase64>$<hashBase64>`
///
/// Note: a 4–6 digit PIN has a tiny keyspace, so the KDF only slows brute
/// force; it is NOT what protects the data at rest. The database is encrypted
/// with a separate random 256-bit key held in the OS keystore (see db_key.dart).
/// The PIN gates the UI; the keystore gates the bytes.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class Pin {
  /// Cost factor. High enough to slow offline guessing, low enough to stay
  /// snappy on a budget phone.
  static const int iterations = 120000;
  static const int _keyLenBytes = 32;
  static const int _saltLenBytes = 16;

  /// Hash a PIN with a fresh random salt, returning the storable string.
  static String hash(String pin) {
    final salt = _randomBytes(_saltLenBytes);
    return hashWithSalt(pin, salt, iterations);
  }

  /// Deterministic variant used by [hash] and by tests.
  static String hashWithSalt(String pin, List<int> salt, int iterations) {
    final dk = pbkdf2(utf8.encode(pin), salt, iterations, _keyLenBytes);
    return 'pbkdf2_sha256\$$iterations\$${base64.encode(salt)}\$${base64.encode(dk)}';
  }

  /// Verify [pin] against a previously stored [stored] string. Returns false on
  /// any malformed input rather than throwing.
  static bool verify(String pin, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } catch (_) {
      return false;
    }
    final actual = pbkdf2(utf8.encode(pin), salt, iterations, expected.length);
    return _constantTimeEquals(actual, expected);
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018). Exposed for testing against known vectors.
  static Uint8List pbkdf2(
      List<int> password, List<int> salt, int iterations, int keyLen) {
    final hmac = Hmac(sha256, password);
    const hLen = 32; // SHA-256 output size
    final blocks = (keyLen / hLen).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blocks; block++) {
      final blockIndex = <int>[
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return out.toBytes().sublist(0, keyLen);
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = rng.nextInt(256);
    }
    return b;
  }

  /// Length-constant comparison to avoid timing side channels.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
