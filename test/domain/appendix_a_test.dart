import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/domain/sample_data.dart';

void main() {
  // Use a fixed "now" inside the same month/day as the seed date so that
  // thisMonth/thisQuarter include every seeded transaction.
  final now = DateTime(2026, 6, 21);
  const seedDate = '2026-06-10';

  late Ledger ledger;
  setUp(() {
    ledger = Ledger(
      products: SampleData.products(0),
      salespersons: SampleData.salespersons(0),
      txns: SampleData.transactions(seedDate, 1000),
      settings: SampleData.settings,
    );
  });

  group('6.1 Product stock', () {
    test('matches Appendix A expected stock', () {
      expect(ledger.stock('p_tsm'), 60);
      expect(ledger.stock('p_tsl'), 60);
      expect(ledger.stock('p_tsxl'), 40);
      expect(ledger.stock('p_sh7'), 20);
      expect(ledger.stock('p_sh8'), 17);
      expect(ledger.stock('p_cps'), 160);
    });
  });

  test('6.4 stock value = 76900', () {
    expect(ledger.stockValue, 76900);
  });

  group('6.3 Salesperson balances', () {
    test('Rahul / Amir / Sana = 6000 / 5600 / 2000', () {
      expect(ledger.balance('s_rahul'), 6000);
      expect(ledger.balance('s_amir'), 5600);
      expect(ledger.balance('s_sana'), 2000);
    });
    test('total owed = 13600', () {
      expect(ledger.totalOwed, 13600);
    });
  });

  test('6.4 cash on hand = 65300', () {
    expect(ledger.cashOnHand, 65300);
  });

  group('6.5 Recognised profit', () {
    test('per salesperson = 3250 / 4000 / 840', () {
      expect(ledger.recognisedProfit('s_rahul'), 3250);
      expect(ledger.recognisedProfit('s_amir'), 4000);
      expect(ledger.recognisedProfit('s_sana'), 840);
    });
    test('total recognised = 8090', () {
      final m = Period.thisMonth(now);
      expect(ledger.recognisedProfitInPeriod(m), 8090);
    });
  });

  group('Period money', () {
    final m = Period.thisMonth(now);
    test('expenses this month = 6200', () {
      expect(ledger.expensesInPeriod(m), 6200);
    });
    test('net profit this month = 1890', () {
      expect(ledger.netProfitInPeriod(m), 1890);
    });
  });

  test('6.7 low stock items (<=20) = SH-7, SH-8', () {
    final low = ledger.lowStockProducts().map((p) => p.id).toSet();
    expect(low, {'p_sh7', 'p_sh8'});
  });

  test('6.7 ranking by goods taken', () {
    final m = Period.thisMonth(now);
    final ranked = ledger.topSalespersons(m);
    expect(ranked.map((e) => e.key.name).toList(), ['Amir', 'Rahul', 'Sana']);
    expect(ranked.map((e) => e.value).toList(), [21600, 16000, 5000]);
  });

  group('Receipt previous balance (Section 10)', () {
    test('previous balance before Rahul sale is opening (0)', () {
      final sale = ledger.txns.firstWhere((t) => t.id == 'sale_rahul');
      expect(ledger.balanceBefore('s_rahul', sale), 0);
    });
    test('previous balance before Rahul payment = 16000 (after sale & return)',
        () {
      final pay = ledger.txns.firstWhere((t) => t.id == 'pay_rahul');
      expect(ledger.balanceBefore('s_rahul', pay), 16000);
    });
  });

  group('Profit never exceeds margin earned', () {
    test('recognised <= sellTaken - costTaken per salesperson', () {
      for (final s in ledger.salespersons) {
        final margin = ledger.sellTaken(s.id) - ledger.costTaken(s.id);
        expect(ledger.recognisedProfit(s.id) <= margin, true,
            reason: '${s.name}: recognised exceeds margin earned');
      }
    });
  });

  group('Opening margin (edge case 6/7)', () {
    test('opening with margin splits cost vs profit on repayment', () {
      // Salesperson owes 1000 opening at 20% margin (200 profit baked in).
      // A single 1000 payment recognises 200 profit; cost recovery 800.
      final s = Salesperson(
          id: 'x', name: 'X', opening: 1000, openingMarginBp: 2000, createdAt: 0);
      final l = Ledger(
        products: const [],
        salespersons: [s],
        txns: [
          Txn(id: 'p', type: TxnType.payment, date: seedDate, createdAt: 1, salespersonId: 'x', amount: 1000),
        ],
        settings: SampleData.settings,
      );
      expect(l.recognisedProfit('x'), 200);
    });
  });

  group('Delete-and-readd consistency (Section 8)', () {
    test('removing the payment zeroes recognised profit and restores owed', () {
      final without = Ledger(
        products: SampleData.products(0),
        salespersons: SampleData.salespersons(0),
        txns: SampleData.transactions(seedDate, 1000)
            .where((t) => t.id != 'pay_rahul')
            .toList(),
        settings: SampleData.settings,
      );
      expect(without.recognisedProfit('s_rahul'), 0);
      expect(without.balance('s_rahul'), 16000);
    });
  });
}
