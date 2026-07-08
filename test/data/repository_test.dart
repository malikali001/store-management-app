import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/models.dart';

/// Exercises the acceptance criteria (Section 17) against a real (in-memory)
/// SQLite database through the repository + domain derivation.
void main() {
  late AppDatabase db;
  late StoreRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = StoreRepository(db);
    // Start from a clean, known catalog.
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.upsertProduct(Product(
        id: 'p1', name: 'Widget', buyPrice: 60, sellPrice: 100, createdAt: now));
    await repo.upsertSalesperson(
        Salesperson(id: 's1', name: 'Sam', createdAt: now));
    await repo.setSetting('opening_cash', '1000');
  });

  tearDown(() => db.close());

  const date = '2026-06-10';

  test('stock-in raises stock and lowers cash', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    final l = await repo.loadLedger();
    expect(l.stock('p1'), 10);
    expect(l.cashOnHand, 1000 - 600);
  });

  test('sale reduces stock and raises owed', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    await repo.addSaleOrReturn(type: TxnType.sale, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60),
    ]);
    final l = await repo.loadLedger();
    expect(l.stock('p1'), 6);
    expect(l.balance('s1'), 400);
  });

  test('payment raises cash, lowers owed, recognises profit', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    await repo.addSaleOrReturn(type: TxnType.sale, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60),
    ]);
    await repo.addPayment(salespersonId: 's1', amount: 100, date: date);
    final l = await repo.loadLedger();
    expect(l.balance('s1'), 300);
    // cash: 1000 - 600 (stockin) + 100 (payment) = 500
    expect(l.cashOnHand, 500);
    // margin ratio = (400-240)/400 = 0.4 → profit on 100 = 40
    expect(l.recognisedProfit('s1'), 40);
  });

  test('return restores stock and lowers owed', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    await repo.addSaleOrReturn(type: TxnType.sale, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60),
    ]);
    await repo.addSaleOrReturn(type: TxnType.returnGoods, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 1, unitSell: 100, unitBuy: 60),
    ]);
    final l = await repo.loadLedger();
    expect(l.stock('p1'), 7);
    expect(l.balance('s1'), 300);
  });

  test('expense lowers cash', () async {
    await repo.addExpense(category: 'Rent', amount: 250, date: date);
    final l = await repo.loadLedger();
    expect(l.cashOnHand, 1000 - 250);
  });

  test('addExpensesBatch posts every expense atomically', () async {
    await repo.addExpensesBatch([
      (category: 'Rent', amount: 300, date: date, recurring: true),
      (category: 'Transport', amount: 120, date: date, recurring: true),
    ]);
    final l = await repo.loadLedger();
    final expenses = l.txns.where((t) => t.type == TxnType.expense).toList();
    expect(expenses.length, 2);
    expect(l.cashOnHand, 1000 - 420);
    // Categories are captured into the expense_category list.
    expect(await repo.listValues('expense_category'),
        containsAll(<String>['Rent', 'Transport']));
  });

  test('deleting a transaction restores prior figures', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    final saleId = await repo.addSaleOrReturn(
        type: TxnType.sale, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60),
    ]);
    var l = await repo.loadLedger();
    expect(l.stock('p1'), 6);
    expect(l.balance('s1'), 400);

    await repo.deleteTransaction(saleId);
    l = await repo.loadLedger();
    expect(l.stock('p1'), 10); // restored
    expect(l.balance('s1'), 0); // restored
  });

  test('product with history cannot be deleted; archive instead', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    expect(() => repo.deleteProduct('p1'), throwsA(isA<DomainError>()));
    await repo.archiveProduct('p1');
    final l = await repo.loadLedger();
    expect(l.product('p1')!.archived, true);
  });

  test('salesperson with balance cannot be removed', () async {
    await repo.addStockIn(productId: 'p1', qty: 10, unitBuy: 60, date: date);
    await repo.addSaleOrReturn(type: TxnType.sale, salespersonId: 's1', date: date, lines: [
      (productId: 'p1', qty: 4, unitSell: 100, unitBuy: 60),
    ]);
    expect(() => repo.deleteSalesperson('s1'), throwsA(isA<DomainError>()));
  });

  test('backup then restore reproduces data exactly', () async {
    await repo.resetToSampleData();
    final before = await repo.loadLedger();
    final backup = await repo.exportBackup();

    // Wipe to a different state, then restore.
    await repo.upsertProduct(Product(
        id: 'junk', name: 'Junk', buyPrice: 1, sellPrice: 2, createdAt: 1));
    await repo.restoreBackup(backup);

    final after = await repo.loadLedger();
    expect(after.products.length, before.products.length);
    expect(after.cashOnHand, before.cashOnHand);
    expect(after.totalOwed, before.totalOwed);
    expect(after.stockValue, before.stockValue);
    expect(after.product('junk'), isNull); // wiped by restore
  });
}
