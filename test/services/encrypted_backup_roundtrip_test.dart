import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/services/backup_crypto.dart';

/// Proves the full password-protected path: real export → encrypt → decrypt →
/// restore reproduces the data, and a wrong password cannot restore.
void main() {
  test('encrypted backup restores on a fresh database with the right password',
      () async {
    final src = AppDatabase(NativeDatabase.memory());
    addTearDown(src.close);
    final srcRepo = StoreRepository(src);
    await srcRepo.resetToSampleData();

    final export = await srcRepo.exportBackup();
    final envelope = await encryptBackup(jsonEncode(export), 's3cret');

    // A different device / fresh database restores from the encrypted file.
    final dst = AppDatabase(NativeDatabase.memory());
    addTearDown(dst.close);
    final dstRepo = StoreRepository(dst);

    final innerStr = await decryptBackup(envelope, 's3cret');
    await dstRepo.restoreBackup(jsonDecode(innerStr) as Map<String, dynamic>);

    final before = await srcRepo.loadLedger();
    final after = await dstRepo.loadLedger();
    expect(after.products.length, before.products.length);
    expect(after.totalOwed, before.totalOwed);
    expect(after.cashOnHand, before.cashOnHand);
  });

  test('wrong password cannot decrypt the backup', () async {
    final src = AppDatabase(NativeDatabase.memory());
    addTearDown(src.close);
    final repo = StoreRepository(src);
    await repo.resetToSampleData();

    final envelope =
        await encryptBackup(jsonEncode(await repo.exportBackup()), 'right');
    expect(() => decryptBackup(envelope, 'wrong'),
        throwsA(isA<BackupPasswordError>()));
  });
}
