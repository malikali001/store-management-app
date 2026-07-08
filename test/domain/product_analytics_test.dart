import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/sample_data.dart';

/// Per-product analytics used by the product detail screen, checked against the
/// Appendix A golden fixture.
void main() {
  late Ledger l;

  setUp(() {
    const date = '2026-06-15';
    l = Ledger(
      products: SampleData.products(1000),
      salespersons: SampleData.salespersons(1000),
      txns: SampleData.transactions(date, 1000),
      settings: SampleData.settings,
    );
  });

  test('units sold is net of returns', () {
    // CP-S: Rahul took 50, returned 10 → net 40 sold.
    expect(l.unitsSold('p_cps'), 40);
    // TS-M: 40 sold, no returns.
    expect(l.unitsSold('p_tsm'), 40);
    // SH-7: 10 sold.
    expect(l.unitsSold('p_sh7'), 10);
  });

  test('sales revenue uses sell snapshots, net of returns', () {
    // CP-S sells at 150: (50 − 10) × 150 = 6000.
    expect(l.salesRevenue('p_cps'), 6000);
    // TS-M sells at 250: 40 × 250 = 10000.
    expect(l.salesRevenue('p_tsm'), 10000);
  });

  test('stock value = remaining stock × buy price', () {
    // CP-S: 200 in − 50 out + 10 back = 160 stock × 90 buy = 14400.
    expect(l.stock('p_cps'), 160);
    expect(l.productStockValue('p_cps'), 160 * 90);
  });

  test('movements include stock-in, sale and return for a product', () {
    // CP-S: 1 stock-in + 1 sale + 1 return = 3 movements.
    final m = l.productMovements('p_cps');
    expect(m.length, 3);
    // Oldest first (stock-in precedes the sale precedes the return).
    expect(m.first.type.wire, 'stockin');
    expect(m.last.type.wire, 'return');
  });

  test('a product with only stock-in has a single movement', () {
    // TS-XL was stocked in but never sold.
    expect(l.unitsSold('p_tsxl'), 0);
    expect(l.productMovements('p_tsxl').length, 1);
  });
}
