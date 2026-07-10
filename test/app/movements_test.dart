import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';

import 'lock_test_support.dart';

/// Exercises stock-in, product detail (add stock / edit), expense entry, and
/// the delete-via-entry-detail correction model.
void main() {
  Future<AppDatabase> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          lockTestOverride(),
        ],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1300, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('add product, stock it in via product detail, then edit it',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    // Add a product.
    await goTab(tester, 'Products');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product_name')), 'Bolt');
    await tester.enterText(find.byKey(const Key('product_buy')), '40');
    await tester.enterText(find.byKey(const Key('product_sell')), '70');
    await tester.tap(find.byKey(const Key('product_save')));
    await tester.pumpAndSettle();

    // Open its detail (the size row reads "Item" for a no-size product) and
    // add stock.
    await tester.tap(find.text('Item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stockin_qty')), '25');
    await tester.enterText(find.byKey(const Key('stockin_buy')), '40');
    await tester.tap(find.byKey(const Key('stockin_save')));
    await tester.pumpAndSettle();

    var ledger = await StoreRepository(db).loadLedger();
    final p = ledger.products.firstWhere((x) => x.name == 'Bolt');
    expect(ledger.stock(p.id), 25);

    // Edit the product's details.
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product_sell')), '80');
    await tester.tap(find.byKey(const Key('product_save')));
    await tester.pumpAndSettle();
    ledger = await StoreRepository(db).loadLedger();
    expect(ledger.products.firstWhere((x) => x.name == 'Bolt').sellPrice, 80);
  });

  testWidgets('add an expense then delete it via the entry sheet',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    // Home → Expense quick action.
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense_category')), 'Rent');
    await tester.enterText(find.byKey(const Key('expense_amount')), '1200');
    await tester.tap(find.byKey(const Key('expense_save')));
    await tester.pumpAndSettle();

    var ledger = await StoreRepository(db).loadLedger();
    expect(ledger.totalExpenses, 1200);

    // Reports → recent expenses → tap the entry → delete it.
    await goTab(tester, 'Reports');
    // The recent-expenses list entry (a ListTile) opens the entry sheet;
    // the category-breakdown row with the same text does not.
    await tester.tap(find.widgetWithText(ListTile, 'Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this entry'));
    await tester.pumpAndSettle();
    // Confirm dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    ledger = await StoreRepository(db).loadLedger();
    expect(ledger.totalExpenses, 0);
  });
}
