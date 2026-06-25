import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/main.dart';

/// End-to-end UI integration tests that drive the real widgets against an
/// (empty by default) in-memory database, then assert both the visible result
/// and the derived totals via the running ledger (loadLedger()).
void main() {
  /// Boots the real app against a fresh in-memory DB. Returns the DB so a
  /// `StoreRepository(db)` can be built for direct ledger assertions.
  Future<AppDatabase> pumpApp(WidgetTester tester, {bool seed = false}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed) await StoreRepository(db).resetToSampleData();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  /// Generous surface so nothing is off-screen / clipped.
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<Ledger> ledgerOf(AppDatabase db) => StoreRepository(db).loadLedger();

  /// Selects [itemText] from an open/closed dropdown that currently shows
  /// (or is found by) [finder]. Opens the menu, then taps the menu item.
  Future<void> selectDropdown(
      WidgetTester tester, Finder dropdown, String itemText) async {
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // The chosen label may appear in both the field and the menu; the menu
    // overlay entry is the last one.
    await tester.tap(find.text(itemText).last);
    await tester.pumpAndSettle();
  }

  /// Adds one product through the product form (assumes the form is open).
  Future<void> fillProductForm(
    WidgetTester tester, {
    required String name,
    required String buy,
    required String sell,
  }) async {
    await tester.enterText(find.byKey(const Key('product_name')), name);
    await tester.enterText(find.byKey(const Key('product_buy')), buy);
    await tester.enterText(find.byKey(const Key('product_sell')), sell);
    await tester.tap(find.byKey(const Key('product_save')));
    await tester.pumpAndSettle();
  }

  /// Goes to a bottom tab by its label.
  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('1. Add a product → appears on Products', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    await goTab(tester, 'Products');
    // Empty state initially.
    expect(find.textContaining('No products yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await fillProductForm(tester, name: 'Wool scarf', buy: '100', sell: '160');

    // Search for it.
    await tester.enterText(
        find.widgetWithText(TextField, 'Search name, brand, code, category'),
        'Wool');
    await tester.pumpAndSettle();
    expect(find.text('Wool scarf'), findsWidgets);

    // Derived: one product exists with the right prices.
    final ledger = await ledgerOf(db);
    expect(ledger.products.length, 1);
    expect(ledger.products.single.name, 'Wool scarf');
    expect(ledger.products.single.sellPrice, 160);
  });

  testWidgets('1b. Products category filter narrows the list', (tester) async {
    bigSurface(tester);
    await pumpApp(tester, seed: true);

    await goTab(tester, 'Products');

    // "All" shows every category (group titles are "brand · name").
    expect(find.textContaining('Cotton tee'), findsWidgets); // T-shirts
    expect(find.textContaining('Runner shoe'), findsWidgets); // Footwear
    expect(find.textContaining('Logo cap'), findsWidgets); // Caps

    // Filter to Footwear → only Runner shoe remains.
    await tester.tap(find.text('Footwear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Runner shoe'), findsWidgets);
    expect(find.textContaining('Cotton tee'), findsNothing);
    expect(find.textContaining('Logo cap'), findsNothing);

    // Back to All → everything returns.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cotton tee'), findsWidgets);
    expect(find.textContaining('Logo cap'), findsWidgets);
  });

  testWidgets('2. Add a salesperson → appears on People', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    await goTab(tester, 'People');
    expect(find.textContaining('No salespersons yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sp_name')), 'Priya');
    await tester.tap(find.byKey(const Key('sp_save')));
    await tester.pumpAndSettle();

    expect(find.text('Priya'), findsWidgets);
    final ledger = await ledgerOf(db);
    expect(ledger.salespersons.single.name, 'Priya');
  });

  testWidgets('3. Stock in a product → stock increases', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    // Precondition: one product.
    final repo = StoreRepository(db);
    final pid = newId();
    await repo.upsertProduct(Product(
      id: pid,
      code: 'WS',
      name: 'Wool scarf',
      brand: '',
      category: '',
      size: '',
      buyPrice: 100,
      sellPrice: 160,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await tester.pumpAndSettle();

    // Stock in via Home quick action.
    await goTab(tester, 'Home');
    final action = find.text('Stock in').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    await selectDropdown(
        tester, find.byKey(const Key('stockin_product')), 'Wool scarf');
    await tester.enterText(find.byKey(const Key('stockin_qty')), '30');
    await tester.enterText(find.byKey(const Key('stockin_buy')), '100');
    await tester.tap(find.byKey(const Key('stockin_save')));
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.stock(pid), 30);

    // Products screen shows the new stock count.
    await goTab(tester, 'Products');
    expect(find.text('30 in stock'), findsWidgets);
  });

  testWidgets('4. Record a sale → receipt shown, owed up, stock down',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final pid = newId();
    await repo.upsertProduct(Product(
      id: pid,
      code: 'WS',
      name: 'Wool scarf',
      brand: '',
      category: '',
      size: '',
      buyPrice: 100,
      sellPrice: 160,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await repo.addStockIn(
        productId: pid, qty: 50, unitBuy: 100, date: _todayIso());
    final spId = newId();
    await repo.upsertSalesperson(Salesperson(
      id: spId,
      name: 'Priya',
      phone: '',
      opening: 0,
      openingMarginBp: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await tester.pumpAndSettle();

    await goTab(tester, 'Home');
    final action = find.text('New sale').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    await selectDropdown(
        tester, find.byKey(const Key('sale_salesperson')), 'Priya');

    // Add one line item.
    await tester.tap(find.byKey(const Key('sale_add_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line_product')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Wool scarf').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('line_qty')), '10');
    await tester.tap(find.byKey(const Key('line_add')));
    await tester.pumpAndSettle();

    // Save the sale.
    await tester.tap(find.byKey(const Key('sale_save')));
    await tester.pumpAndSettle();

    // The sale sheet closed and the receipt opened immediately. This is the
    // regression guard: showReceiptSheet must load a FRESH ledger, not the
    // reactive stream's not-yet-updated snapshot, or the just-saved sale would
    // appear missing.
    expect(find.byKey(const Key('sale_save')), findsNothing);
    expect(find.text('Sale receipt'), findsOneWidget);
    expect(find.text('New balance owed'), findsOneWidget);
    expect(find.text('Sale total'), findsOneWidget);

    // The sale persisted: owed up, stock down.
    final ledger = await ledgerOf(db);
    expect(ledger.balance(spId), 10 * 160); // 1600 owed
    expect(ledger.stock(pid), 40); // 50 - 10
  });

  testWidgets('5. Record a payment → owed down, cash up', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final pid = newId();
    await repo.upsertProduct(Product(
      id: pid,
      code: 'WS',
      name: 'Wool scarf',
      brand: '',
      category: '',
      size: '',
      buyPrice: 100,
      sellPrice: 160,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    final spId = newId();
    await repo.upsertSalesperson(Salesperson(
      id: spId,
      name: 'Priya',
      phone: '',
      opening: 0,
      openingMarginBp: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await repo.addSaleOrReturn(
      type: TxnType.sale,
      salespersonId: spId,
      date: _todayIso(),
      lines: [(productId: pid, qty: 10, unitSell: 160, unitBuy: 100)],
    );
    await tester.pumpAndSettle();

    final cashBefore = (await ledgerOf(db)).cashOnHand;

    await goTab(tester, 'Home');
    final action = find.text('Record payment').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    await selectDropdown(
        tester, find.byKey(const Key('payment_salesperson')), 'Priya');
    await tester.enterText(find.byKey(const Key('payment_amount')), '600');
    await tester.tap(find.byKey(const Key('payment_save')));
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.balance(spId), 1600 - 600); // 1000 owed
    expect(ledger.cashOnHand, cashBefore + 600);
  });

  testWidgets('6. Return goods → stock restored, owed down', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final pid = newId();
    await repo.upsertProduct(Product(
      id: pid,
      code: 'WS',
      name: 'Wool scarf',
      brand: '',
      category: '',
      size: '',
      buyPrice: 100,
      sellPrice: 160,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await repo.addStockIn(
        productId: pid, qty: 50, unitBuy: 100, date: _todayIso());
    final spId = newId();
    await repo.upsertSalesperson(Salesperson(
      id: spId,
      name: 'Priya',
      phone: '',
      opening: 0,
      openingMarginBp: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await repo.addSaleOrReturn(
      type: TxnType.sale,
      salespersonId: spId,
      date: _todayIso(),
      lines: [(productId: pid, qty: 10, unitSell: 160, unitBuy: 100)],
    );
    await tester.pumpAndSettle();
    // After sale: stock 40, owed 1600.

    // Return is reached from the Sales tab.
    await goTab(tester, 'Sales');
    await tester.tap(find.text('Return goods').first);
    await tester.pumpAndSettle();

    await selectDropdown(
        tester, find.byKey(const Key('return_salesperson')), 'Priya');
    await tester.tap(find.byKey(const Key('return_add_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('line_product')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Wool scarf').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('line_qty')), '4');
    await tester.tap(find.byKey(const Key('line_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('return_save')));
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.stock(pid), 44); // 40 + 4
    expect(ledger.balance(spId), 1600 - 4 * 160); // 960
  });

  testWidgets('7. Add an expense → cash decreases', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final cashBefore = (await ledgerOf(db)).cashOnHand;

    await goTab(tester, 'Home');
    final action = find.text('Expense').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('expense_category')), 'Rent');
    await tester.enterText(find.byKey(const Key('expense_amount')), '3000');
    await tester.tap(find.byKey(const Key('expense_save')));
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.cashOnHand, cashBefore - 3000);
    expect(ledger.totalExpenses, 3000);
  });

  testWidgets('8. Delete a transaction → figures revert', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final spId = newId();
    await repo.upsertSalesperson(Salesperson(
      id: spId,
      name: 'Priya',
      phone: '',
      opening: 0,
      openingMarginBp: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    // A payment creates a (negative) balance / cash bump we can revert.
    await repo.addPayment(salespersonId: spId, amount: 500, date: _todayIso());
    await tester.pumpAndSettle();

    final cashWithPayment = (await ledgerOf(db)).cashOnHand;
    expect((await ledgerOf(db)).balance(spId), -500);

    // Open the salesperson ledger from People and tap the payment entry.
    await goTab(tester, 'People');
    await tester.tap(find.text('Priya').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payment received').first);
    await tester.pumpAndSettle();

    // Entry detail sheet → delete.
    await tester.tap(find.text('Delete this entry'));
    await tester.pumpAndSettle();
    // Confirm dialog.
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.txns, isEmpty);
    expect(ledger.balance(spId), 0);
    expect(ledger.cashOnHand, cashWithPayment - 500);
  });

  testWidgets('9. Dashboard reacts to a sale (cash/owed update)',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    // Low-stock threshold 20; stock a product to just above, then sell below.
    final pid = newId();
    await repo.upsertProduct(Product(
      id: pid,
      code: 'WS',
      name: 'Wool scarf',
      brand: '',
      category: '',
      size: '',
      buyPrice: 100,
      sellPrice: 160,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await repo.addStockIn(
        productId: pid, qty: 25, unitBuy: 100, date: _todayIso());
    final spId = newId();
    await repo.upsertSalesperson(Salesperson(
      id: spId,
      name: 'Priya',
      phone: '',
      opening: 0,
      openingMarginBp: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await tester.pumpAndSettle();

    // Sell 10 → stock 15 (≤20, low) and owed becomes 1,600.
    await repo.addSaleOrReturn(
      type: TxnType.sale,
      salespersonId: spId,
      date: _todayIso(),
      lines: [(productId: pid, qty: 10, unitSell: 160, unitBuy: 100)],
    );
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.lowStockProducts().length, 1);
    expect(ledger.totalOwed, 1600);

    // Home reflects the updated owed figure (formatted plain integer).
    await goTab(tester, 'Home');
    expect(find.text('1,600'), findsWidgets);
    // Low-stock chip updated.
    expect(find.textContaining('Low stock · 1'), findsWidgets);
  });

  testWidgets('10. Settings → Load demo data populates Products',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    // Products empty to start.
    await goTab(tester, 'Products');
    expect(find.textContaining('No products yet'), findsOneWidget);

    // Open Settings from the Home gear.
    await goTab(tester, 'Home');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final loadDemo = find.text('Load demo data');
    await tester.ensureVisible(loadDemo);
    await tester.tap(loadDemo);
    await tester.pumpAndSettle();
    // Confirm dialog.
    await tester.tap(find.text('Load demo'));
    await tester.pumpAndSettle();

    final ledger = await ledgerOf(db);
    expect(ledger.products, isNotEmpty);

    // Back to Products: no longer empty.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await goTab(tester, 'Products');
    expect(find.textContaining('No products yet'), findsNothing);
  });
}

/// Local YYYY-MM-DD for today (mirrors the app's todayIso()).
String _todayIso() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
