import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/ledger.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/services/report_pdf.dart';

/// Every report must produce a non-empty PDF that embeds a TrueType font (so it
/// is not blank on web — same guard as the receipt), and must not crash on an
/// empty store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Build inline (no isolate) so the test can await results and coverage sees
  // the build code.
  debugBuildReportsInline = true;

  final fixedNow = DateTime(2026, 7, 9);
  const period = Period.allTime;

  Future<AppDatabase> freshDb({bool demo = false}) async {
    final db = AppDatabase(NativeDatabase.memory());
    if (demo) await StoreRepository(db).seedDemoData();
    return db;
  }

  void expectValidPdf(List<int> bytes) {
    expect(bytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(bytes).contains('FontFile2'), isTrue,
        reason: 'Report PDF must embed a TTF font or it renders blank on web');
  }

  group('with demo data', () {
    test('products report', () async {
      final db = await freshDb(demo: true);
      addTearDown(db.close);
      final l = await StoreRepository(db).loadLedger();
      final bytes = await buildProductsReportPdf(l, l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });

    test('shops report', () async {
      final db = await freshDb(demo: true);
      addTearDown(db.close);
      final l = await StoreRepository(db).loadLedger();
      final bytes = await buildShopsReportPdf(l, l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });

    test('salespersons report', () async {
      final db = await freshDb(demo: true);
      addTearDown(db.close);
      final l = await StoreRepository(db).loadLedger();
      final bytes = await buildSalespersonsReportPdf(l, l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });
  });

  test('reports do not crash on an empty store', () async {
    final db = await freshDb();
    addTearDown(db.close);
    final l = await StoreRepository(db).loadLedger();
    expectValidPdf(await buildProductsReportPdf(l, l.settings, period,
        generatedAt: fixedNow));
    expectValidPdf(await buildShopsReportPdf(l, l.settings, period,
        generatedAt: fixedNow));
    expectValidPdf(await buildSalespersonsReportPdf(l, l.settings, period,
        generatedAt: fixedNow));
  });

  // Regression: a single category / salesperson with more rows than fit on one
  // page must paginate — not hang. (A section table wrapped in a non-splittable
  // Column used to lock up here.)
  test('large per-section reports paginate without hanging', () async {
    const now = 1000;
    const settings = StoreSettings();

    final products = [
      for (var i = 0; i < 220; i++)
        Product(
          id: 'p$i',
          name: 'Item $i',
          category: 'Bulk', // all in ONE category → one very long table
          buyPrice: 10,
          sellPrice: 20,
          createdAt: now,
        ),
    ];
    final txns = <Txn>[
      // ~250 sales for one salesperson → one very long movement table.
      for (var i = 0; i < 250; i++)
        Txn(
          id: 't$i',
          type: TxnType.sale,
          date: '2026-07-0${(i % 9) + 1}',
          createdAt: now + i,
          salespersonId: 's1',
          lines: [
            TxnLine(
                id: 'l$i',
                transactionId: 't$i',
                productId: 'p${i % 220}',
                qty: 1,
                unitSell: 20,
                unitBuy: 10),
          ],
        ),
    ];
    final ledger = Ledger(
      products: products,
      salespersons: const [Salesperson(id: 's1', name: 'Sam', createdAt: now)],
      txns: txns,
      settings: settings,
    );

    expectValidPdf(await buildProductsReportPdf(ledger, settings, period,
        generatedAt: fixedNow));
    expectValidPdf(await buildSalespersonsReportPdf(
        ledger, settings, period,
        generatedAt: fixedNow));
  });
}
