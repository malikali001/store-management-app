import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'lock_test_support.dart';
import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/services/backup_status.dart';

void main() {
  test('first run starts EMPTY with sensible default settings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);

    await repo.seedIfEmpty();
    final l = await repo.loadLedger();

    expect(l.products, isEmpty);
    expect(l.salespersons, isEmpty);
    expect(l.txns, isEmpty);
    // Defaults are written so the app is usable immediately.
    expect(l.settings.currency, 'Rs ');
    expect(l.settings.lowStock, 20);
  });

  test('backup status: stale with data and no backup, fresh after a backup',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    await repo.resetToSampleData(); // gives the store data worth losing

    final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()]);
    addTearDown(container.dispose);
    await container.read(ledgerProvider.future); // first ledger snapshot

    var status = await container.read(backupStatusProvider.future);
    expect(status.hasData, true);
    expect(status.isStale, true); // never backed up → must nudge

    // Simulate a successful backup.
    await repo.setSetting(
        kLastBackupKey, '${DateTime.now().millisecondsSinceEpoch}');
    container.invalidate(backupStatusProvider);
    status = await container.read(backupStatusProvider.future);
    expect(status.isStale, false);
  });

  test('backup status: empty store is never nagged', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).seedIfEmpty(); // empty, defaults only

    final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()]);
    addTearDown(container.dispose);
    await container.read(ledgerProvider.future);

    final status = await container.read(backupStatusProvider.future);
    expect(status.hasData, false);
    expect(status.isStale, false);
  });

  testWidgets('launch shows a backup reminder when data is unprotected',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData(); // data, never backed up

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Back up now'), findsOneWidget); // the nudge banner
  });
}
