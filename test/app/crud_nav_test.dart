import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/main.dart';

/// Proves the full create / edit / remove lifecycle through the real UI, and
/// that every screen and sheet you can enter has a way back (no dead-ends).
void main() {
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<AppDatabase> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  Future<Ledger> ledgerOf(AppDatabase db) => StoreRepository(db).loadLedger();
  int now() => DateTime.now().millisecondsSinceEpoch;

  Future<void> goTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Opens the People tab and selects the Staff (salespersons) segment.
  Future<void> goStaff(WidgetTester tester) async {
    await goTab(tester, 'People');
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
  }

  // ---- EDIT ---------------------------------------------------------------

  testWidgets('Edit a product: change its sell price through the UI',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    await StoreRepository(db).upsertProduct(Product(
        id: 'p1', name: 'Widget', buyPrice: 60, sellPrice: 100, createdAt: now()));
    await tester.pumpAndSettle();

    await goTab(tester, 'Products');
    await tester.tap(find.text('Item').first); // open product actions row
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();

    // Change the sell price and save.
    await tester.enterText(find.byKey(const Key('product_sell')), '150');
    await tester.tap(find.byKey(const Key('product_save')));
    await tester.pumpAndSettle();

    expect((await ledgerOf(db)).product('p1')!.sellPrice, 150);
  });

  testWidgets('Edit a salesperson: rename through the ledger edit action',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    await StoreRepository(db)
        .upsertSalesperson(Salesperson(id: 's1', name: 'Old Name', createdAt: now()));
    await tester.pumpAndSettle();

    await goStaff(tester);
    await tester.tap(find.text('Old Name').first);
    await tester.pumpAndSettle();
    // Edit action in the ledger app bar.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sp_name')), 'New Name');
    await tester.tap(find.byKey(const Key('sp_save')));
    await tester.pumpAndSettle();

    expect((await ledgerOf(db)).salesperson('s1')!.name, 'New Name');
  });

  // ---- REMOVE -------------------------------------------------------------

  testWidgets('Delete a product with no history through the UI',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    await StoreRepository(db).upsertProduct(Product(
        id: 'p1', name: 'Widget', buyPrice: 60, sellPrice: 100, createdAt: now()));
    await tester.pumpAndSettle();

    await goTab(tester, 'Products');
    await tester.tap(find.text('Item').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    // Confirm dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect((await ledgerOf(db)).product('p1'), isNull);
  });

  testWidgets('A product WITH history is archived instead of deleted',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    await repo.upsertProduct(Product(
        id: 'p1', name: 'Widget', buyPrice: 60, sellPrice: 100, createdAt: now()));
    await repo.addStockIn(
        productId: 'p1', qty: 5, unitBuy: 60, date: '2026-06-10');
    await tester.pumpAndSettle();

    await goTab(tester, 'Products');
    await tester.tap(find.text('Item').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete')); // confirm delete
    await tester.pumpAndSettle();
    // Delete is blocked → app offers to archive instead.
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    final l = await ledgerOf(db);
    expect(l.product('p1'), isNotNull); // history preserved
    expect(l.product('p1')!.archived, true); // hidden from lists
  });

  testWidgets('Remove a settled salesperson from the ledger', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    await StoreRepository(db)
        .upsertSalesperson(Salesperson(id: 's1', name: 'Settled Sam', createdAt: now()));
    await tester.pumpAndSettle();

    await goStaff(tester);
    await tester.tap(find.text('Settled Sam').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove salesperson'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect((await ledgerOf(db)).salesperson('s1'), isNull);
    // Popped back to People.
    expect(find.text('Settled Sam'), findsNothing);
  });

  // ---- NAVIGATION: always a way back --------------------------------------

  testWidgets('Settings is reachable and has a back button to Home',
      (tester) async {
    bigSurface(tester);
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    // A back button exists; tapping it returns to Home.
    expect(find.byType(BackButton), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing); // back on a root tab
  });

  testWidgets('Salesperson ledger has a back button to People', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    await StoreRepository(db)
        .upsertSalesperson(Salesperson(id: 's1', name: 'Sam', createdAt: now()));
    await tester.pumpAndSettle();

    await goStaff(tester);
    await tester.tap(find.text('Sam').first);
    await tester.pumpAndSettle();
    expect(find.text('Record payment'), findsWidgets); // on the ledger
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Back on People (Add action visible, no ledger button).
    expect(find.text('Record payment'), findsNothing);
  });

  testWidgets('A form sheet can be dismissed without saving', (tester) async {
    bigSurface(tester);
    await pumpApp(tester);
    await tester.tap(find.text('New sale').first);
    await tester.pumpAndSettle();
    expect(find.text('Save sale'), findsOneWidget);
    // Dismiss the modal sheet by tapping the scrim above it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Save sale'), findsNothing); // back to Home, no dead-end
  });
}
