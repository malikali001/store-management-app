import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/domain/period.dart';

/// Shops (external customers): buying analytics and loyalty segmentation are
/// pure functions of the purchase log, and survive a backup round-trip.
void main() {
  // A fixed "now" so day-based segment thresholds are deterministic.
  final now = DateTime(2026, 7, 8);
  const msPerDay = 86400000;
  int daysAgoMs(int d) => now.millisecondsSinceEpoch - d * msPerDay;
  String daysAgo(int d) {
    final dt = now.subtract(Duration(days: d));
    final m = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$dd';
  }

  group('shopSegment', () {
    Ledger ledgerWith(Shop shop, List<ShopPurchase> purchases) => Ledger(
          products: const [],
          salespersons: const [],
          txns: const [],
          settings: const StoreSettings(),
          shops: [shop],
          shopPurchases: purchases,
        );

    ShopPurchase p(String shopId, int daysAgoN, int amount, int seq) =>
        ShopPurchase(
          id: 'p$seq',
          shopId: shopId,
          date: daysAgo(daysAgoN),
          amount: amount,
          createdAt: seq,
        );

    test('a just-added shop with no purchases is New', () {
      final l = ledgerWith(
          Shop(id: 'a', name: 'A', createdAt: daysAgoMs(5)), const []);
      expect(l.shopSegment('a', now), ShopSegment.fresh);
    });

    test('an old shop that never bought is Inactive', () {
      final l = ledgerWith(
          Shop(id: 'a', name: 'A', createdAt: daysAgoMs(200)), const []);
      expect(l.shopSegment('a', now), ShopSegment.inactive);
    });

    test('a single recent purchase is still New', () {
      final l = ledgerWith(
        Shop(id: 'a', name: 'A', createdAt: daysAgoMs(120)),
        [p('a', 3, 1000, 1)],
      );
      expect(l.shopSegment('a', now), ShopSegment.fresh);
    });

    test('long-term, frequent, recent buyer is Reliable', () {
      final l = ledgerWith(
        Shop(id: 'a', name: 'A', createdAt: daysAgoMs(200)),
        [
          p('a', 180, 1000, 1),
          p('a', 120, 1000, 2),
          p('a', 80, 1000, 3),
          p('a', 40, 1000, 4),
          p('a', 5, 1000, 5),
        ],
      );
      expect(l.shopSegment('a', now), ShopSegment.reliable);
    });

    test('some orders but too few to be reliable is Regular', () {
      final l = ledgerWith(
        Shop(id: 'a', name: 'A', createdAt: daysAgoMs(150)),
        [p('a', 70, 1000, 1), p('a', 40, 1000, 2)],
      );
      expect(l.shopSegment('a', now), ShopSegment.regular);
    });

    test('no purchase in over 90 days is Inactive', () {
      final l = ledgerWith(
        Shop(id: 'a', name: 'A', createdAt: daysAgoMs(300)),
        [p('a', 250, 1000, 1), p('a', 130, 1000, 2)],
      );
      expect(l.shopSegment('a', now), ShopSegment.inactive);
    });
  });

  test('totals, period buying and top-buyer ranking', () {
    final l = Ledger(
      products: const [],
      salespersons: const [],
      txns: const [],
      settings: const StoreSettings(),
      shops: [
        Shop(id: 'a', name: 'A', createdAt: 0),
        Shop(id: 'b', name: 'B', createdAt: 0),
      ],
      shopPurchases: [
        ShopPurchase(
            id: '1', shopId: 'a', date: daysAgo(2), amount: 5000, createdAt: 1),
        ShopPurchase(
            id: '2', shopId: 'a', date: daysAgo(1), amount: 3000, createdAt: 2),
        ShopPurchase(
            id: '3', shopId: 'b', date: daysAgo(1), amount: 4000, createdAt: 3),
      ],
    );

    expect(l.totalBought('a'), 8000);
    expect(l.totalBought('b'), 4000);
    expect(l.purchaseCount('a'), 2);
    expect(l.topBoughtValue, 8000);

    final ranked = l.topShops(Period.thisMonth(now));
    expect(ranked.first.key.id, 'a');
    expect(ranked.first.value, 8000);
  });

  group('repository', () {
    late AppDatabase db;
    late StoreRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = StoreRepository(db);
    });
    tearDown(() => db.close());

    test('add shop + purchases, then delete cascades', () async {
      await repo.upsertShop(Shop(
          id: 'shop1', name: 'Metro', ownerName: 'Kamran', createdAt: 1000));
      await repo.upsertSalesperson(
          Salesperson(id: 's1', name: 'Sam', createdAt: 1000));
      await repo.addShopPurchase(
          shopId: 'shop1', amount: 5000, date: '2026-07-01', salespersonId: 's1');
      await repo.addShopPurchase(
          shopId: 'shop1', amount: 3000, date: '2026-07-05');

      var l = await repo.loadLedger();
      expect(l.shops.single.name, 'Metro');
      expect(l.totalBought('shop1'), 8000);
      expect(l.purchasesOf('shop1').first.salespersonId, 's1');

      await repo.deleteShop('shop1');
      l = await repo.loadLedger();
      expect(l.shops, isEmpty);
      expect(l.shopPurchases, isEmpty); // history removed with the shop
    });

    test('backup round-trip preserves shops and purchases', () async {
      await repo.upsertShop(Shop(id: 'shop1', name: 'Metro', createdAt: 1000));
      await repo.addShopPurchase(
          shopId: 'shop1', amount: 5000, date: '2026-07-01');

      final backup = await repo.exportBackup();
      expect(backup['shops'], isA<List>());
      expect((backup['shops'] as List).length, 1);

      // Wipe via restoring an empty-ish backup, then restore the real one.
      await repo.deleteShop('shop1');
      expect((await repo.loadLedger()).shops, isEmpty);

      await repo.restoreBackup(backup);
      final l = await repo.loadLedger();
      expect(l.shops.single.name, 'Metro');
      expect(l.totalBought('shop1'), 5000);
    });
  });
}
