import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/domain/product_insights.dart';
import 'package:store_manager/domain/sample_data.dart';

/// Product performance insights, checked against the Appendix A golden fixture
/// (which pins every ranking) plus purpose-built fixtures for the figures that
/// need several dates: trend windows, demand rate, and restock urgency.
///
/// `now` is always passed explicitly so nothing here depends on the wall clock.
void main() {
  // ---- Appendix A rankings --------------------------------------------------
  //
  // Per product, in the golden fixture:
  //   TS-M   40 units, revenue 10000, cost 7200, margin 2800 (28%), stock  60
  //   TS-L   20 units, revenue  5000, cost 3600, margin 1400 (28%), stock  60
  //   TS-XL   0 units, revenue     0, cost    0, margin    0       , stock  40
  //   SH-7   10 units, revenue 12000, cost 9000, margin 3000 (25%), stock  20
  //   SH-8    8 units, revenue  9600, cost 7200, margin 2400 (25%), stock  17
  //   CP-S   40 units, revenue  6000, cost 3600, margin 2400 (40%), stock 160
  //          (50 taken less 10 returned — the return nets out of every figure)
  group('Appendix A', () {
    final now = DateTime(2026, 6, 15);
    const date = '2026-06-15';
    late ProductInsights insights;

    List<String> ids(InsightLens lens) =>
        insights.ranked(lens).map((s) => s.product.code).toList();

    setUp(() {
      final ledger = Ledger(
        products: SampleData.products(1000),
        salespersons: SampleData.salespersons(1000),
        txns: SampleData.transactions(date, 1000),
        settings: SampleData.settings,
      );
      insights =
          ProductInsights.build(ledger, Period.thisMonth(now), now);
    });

    test('per-product figures net returns and use price snapshots', () {
      final byCode = {
        for (final s in insights.stats) s.product.code: s,
      };

      expect(byCode['CP-S']!.units, 40); // 50 sold − 10 returned
      expect(byCode['CP-S']!.revenue, 6000); // 40 × 150
      expect(byCode['CP-S']!.cogs, 3600); // 40 × 90
      expect(byCode['CP-S']!.margin, 2400);
      expect(byCode['CP-S']!.marginPct, 40);
      expect(byCode['CP-S']!.stock, 160);
      expect(byCode['CP-S']!.stockValue, 160 * 90);

      expect(byCode['SH-7']!.units, 10);
      expect(byCode['SH-7']!.revenue, 12000);
      expect(byCode['SH-7']!.margin, 3000);
      expect(byCode['SH-7']!.marginPct, 25);

      // Stocked but never sold: no revenue, no margin, stock still counted.
      expect(byCode['TS-XL']!.units, 0);
      expect(byCode['TS-XL']!.revenue, 0);
      expect(byCode['TS-XL']!.stock, 40);
      expect(byCode['TS-XL']!.daysOfCover, isNull); // no measurable demand
    });

    test('fast movers rank by units, ties broken by revenue', () {
      // TS-M and CP-S both moved 40 units; TS-M earned more, so it leads.
      expect(ids(InsightLens.fastMovers),
          ['TS-M', 'CP-S', 'TS-L', 'SH-7', 'SH-8']);
    });

    test('best sellers rank by revenue', () {
      expect(ids(InsightLens.bestSellers),
          ['SH-7', 'TS-M', 'SH-8', 'CP-S', 'TS-L']);
    });

    test('most profit ranks by margin money, ties broken by revenue', () {
      // SH-8 and CP-S both earned 2400; SH-8 sold more, so it leads.
      expect(ids(InsightLens.topProfit),
          ['SH-7', 'TS-M', 'SH-8', 'CP-S', 'TS-L']);
    });

    test('best margin ranks by margin share, not size', () {
      // CP-S is the smallest earner of the three top-margin products but keeps
      // the largest share of each sale (40%).
      expect(ids(InsightLens.bestMargin),
          ['CP-S', 'TS-M', 'TS-L', 'SH-7', 'SH-8']);
    });

    test('thin margin is best margin inverted, worst-and-biggest first', () {
      expect(ids(InsightLens.thinMargin),
          ['SH-7', 'SH-8', 'TS-M', 'TS-L', 'CP-S']);
    });

    test('slow movers put unsold stock first, then least sold', () {
      // TS-XL never sold at all. Ties (TS-M/CP-S at 40 units) break on money
      // tied up, so CP-S (160 × 90 = 14,400) outranks TS-M (60 × 180 = 10,800).
      expect(ids(InsightLens.slowMovers),
          ['TS-XL', 'SH-8', 'SH-7', 'TS-L', 'CP-S', 'TS-M']);
    });

    test('restock ranks by days of cover, least cover first', () {
      // Every sale is dated today, so the demand rate spans a single day:
      // TS-M 60/40 = 1.5 days of cover, SH-7 2.0, SH-8 2.125, TS-L 3.0, CP-S 4.
      // All are inside the 14-day reorder window.
      expect(insights.spanDays, 1);
      expect(ids(InsightLens.restock),
          ['TS-M', 'SH-7', 'SH-8', 'TS-L', 'CP-S']);
      expect(insights.ranked(InsightLens.restock).first.daysOfCover, 1.5);
      // TS-XL has stock but no demand — nothing to reorder for.
      expect(ids(InsightLens.restock), isNot(contains('TS-XL')));
    });

    test('Home headlines show a different product for each lens', () {
      final heads = insights.headlines;
      expect(heads.map((h) => h.$1), ProductInsights.homeLenses);
      expect(heads.first.$2.product.code, 'TS-M'); // the fast mover

      // TS-M also tops "restock soon" and "trending up" here, but those rows
      // step down to the next product rather than repeat it.
      final codes = heads.map((h) => h.$2.product.code).toList();
      expect(codes.toSet().length, codes.length, reason: 'no repeats');
      expect(codes, ['TS-M', 'SH-7', 'SH-8', 'CP-S']);
    });

    test('an empty catalog reports nothing rather than a bottom of the list',
        () {
      final bare = ProductInsights.build(
        Ledger(
            products: SampleData.products(1000),
            salespersons: const [],
            txns: const [],
            settings: SampleData.settings),
        Period.thisMonth(now),
        now,
      );
      expect(bare.isEmpty, isTrue);
      for (final lens in InsightLens.values) {
        expect(bare.ranked(lens), isEmpty, reason: lens.name);
      }
      expect(bare.headlines, isEmpty);
    });
  });

  // ---- Trend windows, demand rate, restock urgency -------------------------
  group('trend and demand', () {
    // A month period ending 31 Mar → 14-day windows: recent 18–31 Mar,
    // previous 4–17 Mar.
    final now = DateTime(2026, 3, 31);
    final period = Period.thisMonth(now);

    /// Two products, same catalog, priced so margins differ.
    List<Product> products() => const [
          Product(
              id: 'p_a',
              code: 'A',
              name: 'Alpha',
              buyPrice: 100,
              sellPrice: 200,
              createdAt: 0),
          Product(
              id: 'p_b',
              code: 'B',
              name: 'Beta',
              buyPrice: 100,
              sellPrice: 150,
              createdAt: 0),
        ];

    var clock = 0;
    Txn stockIn(String pid, int qty, int buy, String date) => Txn(
        id: 'si_${pid}_$date',
        type: TxnType.stockin,
        date: date,
        createdAt: clock += 1000,
        productId: pid,
        qty: qty,
        unitBuy: buy);

    Txn sale(String pid, int qty, int sell, int buy, String date) {
      final id = 'sale_${pid}_$date';
      return Txn(
          id: id,
          type: TxnType.sale,
          date: date,
          createdAt: clock += 1000,
          salespersonId: 's1',
          lines: [
            TxnLine(
                id: '${id}_l',
                transactionId: id,
                productId: pid,
                qty: qty,
                unitSell: sell,
                unitBuy: buy)
          ]);
    }

    setUp(() => clock = 0);

    ProductInsights build(List<Txn> txns, {List<Product>? catalog}) =>
        ProductInsights.build(
          Ledger(
              products: catalog ?? products(),
              salespersons: const [],
              txns: txns,
              settings: SampleData.settings),
          period,
          now,
        );

    test('trending compares the recent window with the one before it', () {
      final insights = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        stockIn('p_b', 100, 100, '2026-03-01'),
        sale('p_a', 5, 200, 100, '2026-03-10'), // previous window
        sale('p_a', 20, 200, 100, '2026-03-25'), // recent window
        sale('p_b', 20, 150, 100, '2026-03-10'), // previous window
        sale('p_b', 5, 150, 100, '2026-03-25'), // recent window
      ]);

      expect(insights.trendWindowDays, 14);

      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.priorUnits, 5);
      expect(a.recentUnits, 20);
      expect(a.trendDelta, 15);

      final b = insights.stats.firstWhere((s) => s.product.id == 'p_b');
      expect(b.trendDelta, -15);

      // Only the product picking up speed is reported.
      expect(insights.ranked(InsightLens.trending).map((s) => s.product.code),
          ['A']);
    });

    test('a first-ever sale in the recent window counts as trending', () {
      final insights = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        sale('p_a', 3, 200, 100, '2026-03-30'),
      ]);
      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.priorUnits, 0);
      expect(a.trendDelta, 3);
      expect(insights.top(InsightLens.trending)?.product.code, 'A');
    });

    test('demand rate averages from the first sale, not the period start', () {
      final insights = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        sale('p_a', 22, 200, 100, '2026-03-10'),
      ]);
      // First sale 10 Mar through 31 Mar inclusive = 22 days, not the full 31.
      expect(insights.spanDays, 22);
      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.dailyUnits, closeTo(1.0, 1e-9));
      expect(a.daysOfCover, closeTo(78, 1e-9)); // 78 left at 1/day
    });

    test('a low count that barely sells is not a restock candidate', () {
      // Low-stock threshold is 20 in the sample settings.
      final insights = build([
        stockIn('p_a', 10, 100, '2026-03-01'),
        sale('p_a', 1, 200, 100, '2026-03-10'), // 1 unit in 22 days
        stockIn('p_b', 30, 100, '2026-03-01'),
        sale('p_b', 25, 150, 100, '2026-03-10'), // 25 units in 22 days
      ]);

      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.stock, 9); // under the threshold…
      expect(a.daysOfCover, greaterThan(100)); // …but months of cover left

      final b = insights.stats.firstWhere((s) => s.product.id == 'p_b');
      expect(b.stock, 5);
      expect(b.daysOfCover, closeTo(4.4, 0.05));

      // Only the one actually running out is reported. A low count on its own is
      // Home's "Low stock" chip, not a reorder signal.
      expect(insights.ranked(InsightLens.restock).map((s) => s.product.code),
          ['B']);
    });

    test('out of stock with live demand is the most urgent restock', () {
      final insights = build([
        stockIn('p_a', 25, 100, '2026-03-01'),
        stockIn('p_b', 100, 100, '2026-03-01'),
        sale('p_a', 25, 200, 100, '2026-03-10'), // clears the shelf
        sale('p_b', 25, 150, 100, '2026-03-10'), // plenty left
      ]);

      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.stock, 0);
      expect(a.daysOfCover, 0);

      final restock =
          insights.ranked(InsightLens.restock).map((s) => s.product.code);
      // B has 75 left at ~1.1/day — about 66 days of cover, nothing to do yet.
      expect(restock, ['A']);
    });

    test('sales outside the period are excluded, stock is always current', () {
      final insights = build([
        stockIn('p_a', 100, 100, '2026-01-05'),
        sale('p_a', 30, 200, 100, '2026-01-20'), // before this month
        sale('p_a', 10, 200, 100, '2026-03-20'), // in this month
      ]);
      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.units, 10); // period-scoped
      expect(a.revenue, 2000);
      expect(a.stock, 60); // 100 − 30 − 10, all time

      // The quarter (Jan–Mar) does include the January sale.
      final quarter = ProductInsights.build(
        Ledger(
            products: products(),
            salespersons: const [],
            txns: [
              stockIn('p_a', 100, 100, '2026-01-05'),
              sale('p_a', 30, 200, 100, '2026-01-20'),
              sale('p_a', 10, 200, 100, '2026-03-20'),
            ],
            settings: SampleData.settings),
        Period.thisQuarter(now),
        now,
      );
      expect(quarter.stats.firstWhere((s) => s.product.id == 'p_a').units, 40);
      expect(quarter.trendWindowDays, 30); // wider windows on a wider period
    });

    test('a product added this fortnight is never called a slow mover', () {
      final fresh = Product(
        id: 'p_new',
        code: 'NEW',
        name: 'Newcomer',
        buyPrice: 100,
        sellPrice: 200,
        // Added 27 Mar — inside the 14-day window, no fair chance to sell.
        createdAt: DateTime(2026, 3, 27).millisecondsSinceEpoch,
      );
      final insights = build(
        [stockIn('p_new', 50, 100, '2026-03-27')],
        catalog: [...products(), fresh],
      );
      expect(insights.ranked(InsightLens.slowMovers).map((s) => s.product.code),
          isNot(contains('NEW')));
    });

    test('archived products drop out of every lens', () {
      final catalog = [
        products().first.copyWith(archived: true),
        products().last,
      ];
      final insights = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        stockIn('p_b', 100, 100, '2026-03-01'),
        sale('p_a', 10, 200, 100, '2026-03-20'),
        sale('p_b', 10, 150, 100, '2026-03-20'),
      ], catalog: catalog);

      expect(insights.stats.map((s) => s.product.code), ['B']);
      for (final lens in InsightLens.values) {
        expect(insights.ranked(lens).map((s) => s.product.code),
            isNot(contains('A')),
            reason: lens.name);
      }
    });

    test('selling below cost surfaces as a negative margin, never as profit',
        () {
      final insights = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        // Sold at 80 against a cost of 100 — a loss of 20 a unit.
        sale('p_a', 10, 80, 100, '2026-03-20'),
      ]);
      final a = insights.stats.firstWhere((s) => s.product.id == 'p_a');
      expect(a.margin, -200);
      expect(a.marginPct, -25);
      expect(insights.ranked(InsightLens.topProfit), isEmpty);
      expect(insights.ranked(InsightLens.bestMargin), isEmpty);
      expect(insights.top(InsightLens.thinMargin)?.product.code, 'A');
    });

    test('deleting the sale returns every insight to its prior state', () {
      final before = build([stockIn('p_a', 100, 100, '2026-03-01')]);
      final after = build([
        stockIn('p_a', 100, 100, '2026-03-01'),
        sale('p_a', 10, 200, 100, '2026-03-20'),
      ]);
      // Same ledger minus the sale — derived figures, so they simply reverse.
      final reverted = build([stockIn('p_a', 100, 100, '2026-03-01')]);

      expect(after.top(InsightLens.fastMovers)?.product.code, 'A');
      expect(reverted.ranked(InsightLens.fastMovers), isEmpty);
      expect(reverted.stats.firstWhere((s) => s.product.id == 'p_a').stock,
          before.stats.firstWhere((s) => s.product.id == 'p_a').stock);
    });
  });
}
