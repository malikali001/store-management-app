import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/services/backup_crypto.dart';

void main() {
  const sample =
      '{"version":1,"products":[{"id":"p1","name":"Widget"}],"settings":{}}';

  test('encrypt → decrypt round-trips with the right password', () async {
    final env = await encryptBackup(sample, 'hunter2');
    expect(isEncryptedBackup(env), isTrue);
    // The ciphertext must not contain the plaintext.
    expect(jsonEncode(env).contains('Widget'), isFalse);

    final back = await decryptBackup(env, 'hunter2');
    expect(back, sample);
  });

  test('wrong password is rejected', () async {
    final env = await encryptBackup(sample, 'correct-horse');
    expect(() => decryptBackup(env, 'wrong-horse'),
        throwsA(isA<BackupPasswordError>()));
  });

  test('tampered ciphertext is rejected', () async {
    final env = await encryptBackup(sample, 'pw');
    // Flip a byte in the base64 ciphertext.
    final ct = env['ciphertext'] as String;
    env['ciphertext'] = (ct[0] == 'A' ? 'B' : 'A') + ct.substring(1);
    expect(() => decryptBackup(env, 'pw'),
        throwsA(isA<BackupPasswordError>()));
  });

  test('a plain (unencrypted) backup is not flagged as encrypted', () {
    expect(isEncryptedBackup({'products': [], 'settings': {}}), isFalse);
  });

  test('two encryptions of the same data differ (random salt + nonce)',
      () async {
    final a = await encryptBackup(sample, 'pw');
    final b = await encryptBackup(sample, 'pw');
    expect(a['ciphertext'], isNot(equals(b['ciphertext'])));
    expect(a['salt'], isNot(equals(b['salt'])));
  });
}
