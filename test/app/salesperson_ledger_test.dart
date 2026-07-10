import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/models.dart' show Product, Salesperson, TxnType;
import 'package:store_manager/screens/salesperson_ledger_screen.dart';

import 'lock_test_support.dart';

/// The salesperson ledger and delete-via-entry-detail for payment and return
/// entries (the sale entry opens a receipt instead).
void main() {
  testWidgets('ledger shows movements; deleting entries re-derives balance',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.upsertSalesperson(Salesperson(id: 's1', name: 'Sam', createdAt: now));
    await repo.upsertProduct(
        Product(id: 'p1', name: 'Widget', buyPrice: 60, sellPrice: 100, createdAt: now));
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: '2026-01-01');
    await repo.addSaleOrReturn(
        type: TxnType.sale,
        salespersonId: 's1',
        date: '2026-01-02',
        lines: [(productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60)]);
    await repo.addPayment(salespersonId: 's1', amount: 100, date: '2026-01-03');
    await repo.addSaleOrReturn(
        type: TxnType.returnGoods,
        salespersonId: 's1',
        date: '2026-01-04',
        lines: [(productId: 'p1', qty: 1, unitSell: 100, unitBuy: 60)]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        lockTestOverride(),
      ],
      child: const MaterialApp(
          home: SalespersonLedgerScreen(salespersonId: 's1')),
    ));
    await tester.pumpAndSettle();

    // balance = 400 (sale) - 100 (payment) - 100 (return) = 200
    expect((await repo.loadLedger()).balance('s1'), 200);
    expect(find.text('Took goods'), findsWidgets);
    expect(find.text('Payment received'), findsWidgets);
    expect(find.text('Returned goods'), findsWidgets);

    // Delete the payment via its entry sheet → balance rises by 100.
    await tester.tap(find.text('Payment received'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await repo.loadLedger()).balance('s1'), 300);

    // Delete the return via its entry sheet → balance rises by 100 more.
    await tester.tap(find.text('Returned goods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await repo.loadLedger()).balance('s1'), 400);
  });
}
