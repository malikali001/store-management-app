import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';

/// productCogs / productGrossMargin against the Appendix A golden data.
void main() {
  test('per-product cost of goods sold and gross margin', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    await repo.resetToSampleData();
    final l = await repo.loadLedger();

    String idFor(String code) =>
        l.products.firstWhere((p) => p.code == code).id;

    // TS-M: Rahul took 40 @ sell 250 / buy 180, no returns.
    final tsm = idFor('TS-M');
    expect(l.salesRevenue(tsm), 40 * 250);
    expect(l.productCogs(tsm), 40 * 180);
    expect(l.productGrossMargin(tsm), 40 * 250 - 40 * 180); // 2800

    // CP-S: sold 50, returned 10 → net 40 @ sell 150 / buy 90.
    final cps = idFor('CP-S');
    expect(l.salesRevenue(cps), (50 - 10) * 150); // 6000
    expect(l.productCogs(cps), (50 - 10) * 90); // 3600
    expect(l.productGrossMargin(cps), 6000 - 3600); // 2400

    // A product never sold has zero revenue, cogs and margin.
    final tsxl = idFor('TS-XL');
    expect(l.salesRevenue(tsxl), 0);
    expect(l.productGrossMargin(tsxl), 0);
  });
}
