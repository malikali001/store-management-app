import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart' show startupDatabaseTimeout;

/// Startup must never leave the user on a blank screen.
///
/// `main()` opens the database before calling `runApp`, so a database that
/// *stalls* (rather than throws) would mean no first frame at all — a white
/// screen with nothing to explain it. The bounded wait in `main()` is what turns
/// that into the startup error screen, so the deadline is asserted here.
void main() {
  test('a startup deadline is set, and it is a sane length', () {
    expect(startupDatabaseTimeout.inSeconds, greaterThanOrEqualTo(5),
        reason: 'a cold wasm/OPFS open needs room to breathe');
    expect(startupDatabaseTimeout.inSeconds, lessThanOrEqualTo(30),
        reason: 'longer than this reads as a hung app');
  });

  test('a database that never opens surfaces as a timeout, not a hang',
      () async {
    // A connection whose open never completes — the web wasm-worker stall this
    // guard exists for.
    final db = AppDatabase(LazyDatabase(() => Completer<QueryExecutor>().future));
    // Deliberately not closed: `close()` awaits the open that never completes,
    // so it would hang the test the same way it would hang startup. Nothing was
    // ever opened, so there is no resource to release.

    await expectLater(
      StoreRepository(db)
          .seedIfEmpty()
          .timeout(const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a healthy database opens well inside the deadline', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // The same call `main()` makes, with the real deadline.
    await StoreRepository(db).seedIfEmpty().timeout(startupDatabaseTimeout);

    // Settings exist, so the app would have started normally.
    final ledger = await StoreRepository(db).loadLedger();
    expect(ledger.settings.storeName, isNotEmpty);
  });
}
