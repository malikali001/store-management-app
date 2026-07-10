import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/services/backup_status.dart';

import 'lock_test_support.dart';

/// The month-start recurring-expense prompt: a recurring expense from a prior
/// month should be offered for this month, and adding it posts a copy.
void main() {
  testWidgets('month-start prompt offers and posts recurring expenses',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);

    // A recurring expense tagged last month (so it is "due" this month).
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 15);
    await repo.addExpense(
      category: 'Rent',
      amount: 3000,
      date: Period.fmtDate(lastMonth),
      recurring: true,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        lockTestOverride(),
        // Resolve the backup-status nudge synchronously so its FutureProvider
        // isn't mid-load at teardown.
        backupStatusProvider.overrideWith(
            (ref) async => const BackupStatus(lastBackup: null, hasData: false)),
      ],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();

    // The prompt appears at startup.
    expect(find.text('Monthly expenses'), findsOneWidget);
    await tester.tap(find.text('Add 1 to this month'));
    await tester.pumpAndSettle();

    // A copy is now posted in the current month.
    final ledger = await repo.loadLedger();
    final thisMonth = Period.thisMonth(now);
    final posted = ledger.txns.where((t) =>
        t.type.wire == 'expense' &&
        (t.category == 'Rent') &&
        thisMonth.contains(t.date));
    expect(posted, isNotEmpty);
  });
}
