/// Password-protected backups. A backup can be encrypted with a passphrase so
/// that restoring it on another device requires that passphrase.
///
/// Scheme: derive a 256-bit key from the passphrase with PBKDF2-HMAC-SHA256
/// (reusing the tested [Pin.pbkdf2]) and a random salt, then encrypt the JSON
/// with AES-GCM (authenticated: a wrong password or a tampered file fails to
/// decrypt rather than yielding garbage). Pure Dart — unit-tested.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/pin.dart';

/// Thrown when decryption fails — wrong password or a corrupted/tampered file.
class BackupPasswordError implements Exception {
  final String message;
  BackupPasswordError(
      [this.message = 'Wrong password, or the backup file is corrupted.']);
  @override
  String toString() => message;
}

const _kEncryptedFormat = 'store-backup-encrypted';
const _kIterations = 120000;
const _kNonceLen = 12;
const _kSaltLen = 16;

/// True if [json] is an encrypted backup envelope (vs a plain backup).
bool isEncryptedBackup(Map<String, dynamic> json) =>
    json['format'] == _kEncryptedFormat;

/// Encrypt [plaintextJson] under [passphrase], returning the storable envelope.
Future<Map<String, dynamic>> encryptBackup(
    String plaintextJson, String passphrase) async {
  final salt = _randomBytes(_kSaltLen);
  final keyBytes = Pin.pbkdf2(utf8.encode(passphrase), salt, _kIterations, 32);
  final algo = AesGcm.with256bits();
  final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
  final nonce = _randomBytes(_kNonceLen);
  final box = await algo.encrypt(
    utf8.encode(plaintextJson),
    secretKey: secretKey,
    nonce: nonce,
  );
  return {
    'format': _kEncryptedFormat,
    'version': 1,
    'kdf': 'pbkdf2_sha256',
    'iterations': _kIterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(box.nonce),
    'ciphertext': base64.encode(box.cipherText),
    'mac': base64.encode(box.mac.bytes),
  };
}

/// Decrypt an encrypted [json] envelope with [passphrase], returning the inner
/// backup JSON string. Throws [BackupPasswordError] on a wrong password or a
/// malformed/tampered file.
Future<String> decryptBackup(
    Map<String, dynamic> json, String passphrase) async {
  try {
    final iterations = (json['iterations'] as num?)?.toInt() ?? _kIterations;
    final salt = base64.decode(json['salt'] as String);
    final nonce = base64.decode(json['nonce'] as String);
    final cipher = base64.decode(json['ciphertext'] as String);
    final mac = base64.decode(json['mac'] as String);
    final keyBytes =
        Pin.pbkdf2(utf8.encode(passphrase), salt, iterations, 32);
    final algo = AesGcm.with256bits();
    final secretKey = await algo.newSecretKeyFromBytes(keyBytes);
    final clear = await algo.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw BackupPasswordError();
  } on BackupPasswordError {
    rethrow;
  } catch (_) {
    throw BackupPasswordError();
  }
}

Uint8List _randomBytes(int n) {
  final rng = Random.secure();
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = rng.nextInt(256);
  }
  return b;
}
