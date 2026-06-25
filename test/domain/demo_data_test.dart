import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/demo_data.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/period.dart';

/// The realistic starter dataset must be internally consistent and rich enough
/// that the dashboard, every period, and the reports show meaningful figures.
void main() {
  final now = DateTime(2026, 6, 22);
  late Ledger l;

  setUp(() {
    final d = DemoData.build(now, createdBase: 1000);
    l = Ledger(
      products: d.products,
      salespersons: d.salespersons,
      txns: d.txns,
      settings: DemoData.settings,
    );
  });

  test('no product ever goes negative in stock', () {
    for (final p in l.products) {
      expect(l.stock(p.id) >= 0, true, reason: '${p.name} ${p.size} < 0');
    }
  });

  test('balances are non-negative and total owed is meaningful', () {
    for (final s in l.salespersons) {
      expect(l.balance(s.id) >= 0, true, reason: '${s.name} owes negative');
    }
    expect(l.totalOwed > 0, true);
  });

  test('cash on hand stays positive', () {
    expect(l.cashOnHand > 0, true);
  });

  test('recognised profit is positive and within margin earned', () {
    var totalProfit = 0;
    for (final s in l.salespersons) {
      // Margin earned on goods plus any margin baked into the opening balance.
      final openingMargin = (s.opening * s.openingMarginBp) ~/ 10000;
      final margin = l.sellTaken(s.id) - l.costTaken(s.id) + openingMargin;
      expect(l.recognisedProfit(s.id) <= margin, true,
          reason: '${s.name}: profit exceeds margin earned');
      totalProfit += l.recognisedProfit(s.id);
    }
    expect(totalProfit > 0, true);
  });

  test('every period has activity (month, quarter, all-time)', () {
    for (final kind in PeriodKind.values) {
      final p = Period.forKind(kind, now);
      expect(l.recognisedProfitInPeriod(p) != 0 || l.expensesInPeriod(p) != 0,
          true,
          reason: '$kind has no money activity');
    }
  });

  test('low-stock alert and rankings have content to show', () {
    expect(l.lowStockProducts().isNotEmpty, true);
    expect(l.topSalespersons(Period.thisMonth(now)).isNotEmpty, true);
    expect(l.topSalespersons(Period.allTime).length, l.salespersons.length);
  });
}
