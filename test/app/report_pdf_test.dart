import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/app/format.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/services/report_pdf.dart';

/// Every report must produce a non-empty PDF that embeds a TrueType font (so it
/// is not blank on web — same guard as the receipt), and must not crash on an
/// empty store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      final bytes = await buildProductsReportPdf(
          l, Money(l.settings), l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });

    test('shops report', () async {
      final db = await freshDb(demo: true);
      addTearDown(db.close);
      final l = await StoreRepository(db).loadLedger();
      final bytes = await buildShopsReportPdf(
          l, Money(l.settings), l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });

    test('salespersons report', () async {
      final db = await freshDb(demo: true);
      addTearDown(db.close);
      final l = await StoreRepository(db).loadLedger();
      final bytes = await buildSalespersonsReportPdf(
          l, Money(l.settings), l.settings, period,
          generatedAt: fixedNow);
      expectValidPdf(bytes);
    });
  });

  test('reports do not crash on an empty store', () async {
    final db = await freshDb();
    addTearDown(db.close);
    final l = await StoreRepository(db).loadLedger();
    final money = Money(l.settings);
    expectValidPdf(await buildProductsReportPdf(l, money, l.settings, period,
        generatedAt: fixedNow));
    expectValidPdf(await buildShopsReportPdf(l, money, l.settings, period,
        generatedAt: fixedNow));
    expectValidPdf(await buildSalespersonsReportPdf(l, money, l.settings, period,
        generatedAt: fixedNow));
  });
}
