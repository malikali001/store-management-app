import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson, Shop;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/models.dart' show Shop;
import 'package:store_manager/main.dart';

import 'lock_test_support.dart';

/// Drives the whole Shops (external customers) flow through the real widgets:
/// add a shop, open its detail, record a purchase, edit it, and delete it.
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
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('add a shop, record a purchase, and see it reflected',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);

    // People tab defaults to Shops.
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No shops yet'), findsOneWidget);

    // Add a shop.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shop_name')), 'Corner Mart');
    await tester.tap(find.byKey(const Key('shop_save')));
    await tester.pumpAndSettle();
    expect(find.text('Corner Mart'), findsWidgets);

    // Open its detail and record a purchase.
    await tester.tap(find.text('Corner Mart').first);
    await tester.pumpAndSettle();
    expect(find.text('Record purchase'), findsWidgets);

    await tester.tap(find.text('Record purchase').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('purchase_amount')), '500');
    await tester.tap(find.byKey(const Key('purchase_save')));
    await tester.pumpAndSettle();

    // Verify via the derived ledger.
    final ledger = await StoreRepository(db).loadLedger();
    final shop = ledger.shops.firstWhere((s) => s.name == 'Corner Mart');
    expect(ledger.totalBought(shop.id), 500);
    expect(ledger.purchaseCount(shop.id), 1);
  });

  testWidgets('search filters the shop list', (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.upsertShop(Shop(id: 's1', name: 'Alpha Store', createdAt: now));
    await repo.upsertShop(Shop(id: 's2', name: 'Beta Bazaar', createdAt: now));
    await tester.pumpAndSettle();

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Store'), findsWidgets);
    expect(find.text('Beta Bazaar'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'beta');
    await tester.pumpAndSettle();
    expect(find.text('Alpha Store'), findsNothing);
    expect(find.text('Beta Bazaar'), findsWidgets);
  });

  testWidgets('edit a shop, delete a purchase, and remove the shop',
      (tester) async {
    bigSurface(tester);
    final db = await pumpApp(tester);
    final repo = StoreRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.upsertShop(Shop(id: 's1', name: 'Old Name', createdAt: now));
    await repo.addShopPurchase(shopId: 's1', amount: 300, date: '2026-01-05');
    await tester.pumpAndSettle();

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Name').first);
    await tester.pumpAndSettle();

    // Edit the shop's name via the edit action.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shop_name')), 'New Name');
    await tester.tap(find.byKey(const Key('shop_save')));
    await tester.pumpAndSettle();
    expect(find.text('New Name'), findsWidgets);

    // Delete the purchase (its row is the last occurrence of the date; the
    // first is the "last purchase" summary figure).
    await tester.tap(find.text('5 Jan 2026').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect((await repo.loadLedger()).totalBought('s1'), 0);

    // Remove the shop.
    await tester.ensureVisible(find.text('Remove shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove shop'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect((await repo.loadLedger()).shops, isEmpty);
  });
}
