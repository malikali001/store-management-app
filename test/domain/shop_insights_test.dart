import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/demo_data.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/domain/shop_insights.dart';

/// Customer (shop) insights. Checked against the demo dataset, which is built
/// with a deliberate spread of behaviours — Metro Mart is the big reliable
/// buyer, Hilltop is steady, Corner is occasional, Fresh Picks is brand new and
/// Old Bazaar has gone quiet — plus hand-built fixtures for the timing rules.
///
/// `now` is always injected so nothing depends on the wall clock.
void main() {
  // ---- The demo dataset ----------------------------------------------------
  group('demo customers', () {
    final now = DateTime(2026, 8, 6);
    late Ledger ledger;

    List<String> names(ShopInsights i, ShopLens lens) =>
        i.ranked(lens).map((s) => s.shop.name).toList();

    setUp(() {
      final b = DemoData.build(now, createdBase: 1000);
      ledger = Ledger(
        products: b.products,
        salespersons: b.salespersons,
        txns: b.txns,
        settings: DemoData.settings,
        shops: DemoData.shops(now.millisecondsSinceEpoch),
        shopPurchases:
            DemoData.shopPurchases(now, createdBase: now.millisecondsSinceEpoch),
      );
    });

    test('all-time top buyers follow total spend', () {
      final i = ShopInsights.build(ledger, Period.allTime, now);
      // Metro 338,000 · Hilltop 65,000 · Old Bazaar 54,000 · Corner 17,000 ·
      // Fresh Picks 6,000.
      expect(names(i, ShopLens.topBuyers), [
        'Metro Mart',
        'Hilltop Traders',
        'Old Bazaar Supplies',
        'Corner Store',
        'Fresh Picks',
      ]);
      final metro = i.stats.firstWhere((s) => s.shop.name == 'Metro Mart');
      expect(metro.totalBought, 338000);
      expect(metro.totalOrders, 7);
      expect(metro.segment, ShopSegment.reliable);
    });

    test('most orders and biggest orders are different questions', () {
      final i = ShopInsights.build(ledger, Period.allTime, now);
      // Metro leads on both here, but the averages tell them apart: Metro
      // averages 48,285 an order against Hilltop's 13,000.
      final metro = i.stats.firstWhere((s) => s.shop.name == 'Metro Mart');
      final hilltop = i.stats.firstWhere((s) => s.shop.name == 'Hilltop Traders');
      expect(metro.orders, 7);
      expect(metro.averageOrder, 48286); // 338000 / 7, rounded
      expect(hilltop.averageOrder, 13000); // 65000 / 5

      expect(names(i, ShopLens.mostOrders).first, 'Metro Mart');
      expect(names(i, ShopLens.biggestOrders).first, 'Metro Mart');
      // Corner Store averages 8,500 — ahead of Fresh Picks' 6,000 despite
      // having spent less per period than the newcomer in some windows.
      expect(names(i, ShopLens.biggestOrders),
          contains('Corner Store'));
    });

    test('Old Bazaar has gone quiet; recent buyers have not', () {
      final i = ShopInsights.build(ledger, Period.allTime, now);
      final quiet = names(i, ShopLens.goneQuiet);
      expect(quiet, ['Old Bazaar Supplies']); // last order 130 days ago

      final bazaar =
          i.stats.firstWhere((s) => s.shop.name == 'Old Bazaar Supplies');
      expect(bazaar.daysSinceLastPurchase, 130);
      expect(bazaar.segment, ShopSegment.inactive);

      // Metro bought 3 days ago — nowhere near the quiet threshold.
      final metro = i.stats.firstWhere((s) => s.shop.name == 'Metro Mart');
      expect(metro.daysSinceLastPurchase, 3);
      expect(quiet, isNot(contains('Metro Mart')));
    });

    test('every shop in the demo set has bought at least once', () {
      final i = ShopInsights.build(ledger, Period.allTime, now);
      expect(i.ranked(ShopLens.neverBought), isEmpty);
      expect(i.isEmpty, isFalse);
    });

    test('headlines name four different customers', () {
      final i = ShopInsights.build(ledger, Period.allTime, now);
      final ids = i.headlines.map((h) => h.$2.shop.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'no repeats');
      expect(i.headlines.first.$1, ShopLens.topBuyers);
      expect(i.headlines.first.$2.shop.name, 'Metro Mart');
    });
  });

  // ---- Timing rules --------------------------------------------------------
  group('trend windows and silence', () {
    final now = DateTime(2026, 8, 6);
    // An all-time period → 90-day trend windows, ending today:
    // recent 9 May–6 Aug, previous 8 Feb–8 May.
    const period = Period.allTime;

    String daysAgo(int d) => Period.fmtDate(now.subtract(Duration(days: d)));
    int daysAgoMs(int d) =>
        now.subtract(Duration(days: d)).millisecondsSinceEpoch;

    var seq = 0;
    ShopPurchase buy(String shopId, int daysAgoN, int amount) => ShopPurchase(
          id: 'p${seq++}',
          shopId: shopId,
          date: daysAgo(daysAgoN),
          amount: amount,
          createdAt: seq,
        );

    ShopInsights build(List<Shop> shops, List<ShopPurchase> purchases) =>
        ShopInsights.build(
          Ledger(
            products: const [],
            salespersons: const [],
            txns: const [],
            settings: const StoreSettings(),
            shops: shops,
            shopPurchases: purchases,
          ),
          period,
          now,
        );

    setUp(() => seq = 0);

    test('windows are wider than the product ones, by period', () {
      expect(ShopInsights.trendWindowFor(PeriodKind.month), 30);
      expect(ShopInsights.trendWindowFor(PeriodKind.quarter), 60);
      expect(ShopInsights.trendWindowFor(PeriodKind.allTime), 90);
    });

    test('growing and shrinking customers are separated', () {
      final shops = [
        Shop(id: 'up', name: 'Rising', createdAt: daysAgoMs(300)),
        Shop(id: 'down', name: 'Falling', createdAt: daysAgoMs(300)),
      ];
      final i = build(shops, [
        buy('up', 120, 5000), // previous window
        buy('up', 20, 20000), // recent window
        buy('down', 120, 20000), // previous window
        buy('down', 20, 5000), // recent window
      ]);

      final up = i.stats.firstWhere((s) => s.shop.id == 'up');
      expect(up.priorBought, 5000);
      expect(up.recentBought, 20000);
      expect(up.trendDelta, 15000);

      expect(i.ranked(ShopLens.buyingMore).map((s) => s.shop.name), ['Rising']);
      expect(i.ranked(ShopLens.buyingLess).map((s) => s.shop.name), ['Falling']);
    });

    test('a brand-new customer is growing, not shrinking', () {
      final i = build(
        [Shop(id: 'a', name: 'Newcomer', createdAt: daysAgoMs(10))],
        [buy('a', 5, 4000)],
      );
      final a = i.stats.single;
      expect(a.priorBought, 0);
      expect(a.trendDelta, 4000);
      expect(i.top(ShopLens.buyingMore)?.shop.name, 'Newcomer');
      // Nothing to decline from, so it is absent from "buying less".
      expect(i.ranked(ShopLens.buyingLess), isEmpty);
    });

    test('a customer who stopped entirely counts as buying less', () {
      final i = build(
        [Shop(id: 'a', name: 'Stopped', createdAt: daysAgoMs(300))],
        [buy('a', 120, 30000)], // previous window only
      );
      final a = i.stats.single;
      expect(a.recentBought, 0);
      expect(a.trendDelta, -30000);
      expect(i.top(ShopLens.buyingLess)?.shop.name, 'Stopped');
      expect(i.ranked(ShopLens.buyingMore), isEmpty);
      // …and is also flagged as quiet, 120 days since the last order.
      expect(i.top(ShopLens.goneQuiet)?.daysSinceLastPurchase, 120);
    });

    test('gone quiet ranks the longest silence first and ignores the recent', () {
      final shops = [
        Shop(id: 'old', name: 'Long gone', createdAt: daysAgoMs(400)),
        Shop(id: 'mid', name: 'Slipping', createdAt: daysAgoMs(400)),
        Shop(id: 'now', name: 'Active', createdAt: daysAgoMs(400)),
      ];
      final i = build(shops, [
        buy('old', 200, 1000),
        buy('mid', 60, 1000), // past the 45-day threshold
        buy('now', 10, 1000), // still recent
      ]);
      expect(i.ranked(ShopLens.goneQuiet).map((s) => s.shop.name),
          ['Long gone', 'Slipping']);
      expect(ShopInsights.quietAfterDays, 45);
    });

    test('a shop added but never served is reported, longest wait first', () {
      final shops = [
        Shop(id: 'a', name: 'Waiting longest', createdAt: daysAgoMs(90)),
        Shop(id: 'b', name: 'Waiting a while', createdAt: daysAgoMs(30)),
        Shop(id: 'c', name: 'Bought once', createdAt: daysAgoMs(60)),
      ];
      final i = build(shops, [buy('c', 5, 1000)]);

      expect(i.ranked(ShopLens.neverBought).map((s) => s.shop.name),
          ['Waiting longest', 'Waiting a while']);
      expect(i.ranked(ShopLens.neverBought).first.daysSinceAdded, 90);
      // A shop that has never bought cannot be "gone quiet" — different fix.
      expect(i.ranked(ShopLens.goneQuiet), isEmpty);
    });

    test('period scoping bounds the money, relationship figures stay all-time',
        () {
      final shops = [Shop(id: 'a', name: 'A', createdAt: daysAgoMs(400))];
      final purchases = [
        buy('a', 200, 10000), // long before this month
        buy('a', 2, 3000), // this month
      ];

      final month = ShopInsights.build(
        Ledger(
            products: const [],
            salespersons: const [],
            txns: const [],
            settings: const StoreSettings(),
            shops: shops,
            shopPurchases: purchases),
        Period.thisMonth(now),
        now,
      );
      final a = month.stats.single;
      expect(a.bought, 3000); // period-scoped
      expect(a.orders, 1);
      expect(a.totalBought, 13000); // all-time
      expect(a.totalOrders, 2);
      expect(a.daysSinceLastPurchase, 2); // all-time recency
    });

    test('archived shops drop out of every lens', () {
      final shops = [
        Shop(id: 'a', name: 'Gone', createdAt: daysAgoMs(200), archived: true),
        Shop(id: 'b', name: 'Here', createdAt: daysAgoMs(200)),
      ];
      final i = build(shops, [buy('a', 5, 9000), buy('b', 5, 1000)]);
      expect(i.stats.map((s) => s.shop.name), ['Here']);
      for (final lens in ShopLens.values) {
        expect(i.ranked(lens).map((s) => s.shop.name), isNot(contains('Gone')),
            reason: lens.name);
      }
    });

    test('no customers at all reports nothing rather than empty rankings', () {
      final i = build(const [], const []);
      expect(i.isEmpty, isTrue);
      expect(i.headlines, isEmpty);
      for (final lens in ShopLens.values) {
        expect(i.ranked(lens), isEmpty, reason: lens.name);
      }
    });

    test('deleting a purchase reverses every figure', () {
      final shops = [Shop(id: 'a', name: 'A', createdAt: daysAgoMs(300))];
      final withBuy = build(shops, [buy('a', 5, 5000)]);
      expect(withBuy.top(ShopLens.topBuyers)?.shop.name, 'A');

      final without = build(shops, const []);
      expect(without.ranked(ShopLens.topBuyers), isEmpty);
      expect(without.stats.single.totalBought, 0);
      // With no history it becomes a "never bought" follow-up instead.
      expect(without.top(ShopLens.neverBought)?.shop.name, 'A');
    });
  });
}
