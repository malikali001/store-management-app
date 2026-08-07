import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/period.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/screens/home_screen.dart' show seeAllSalespersonsKey;
import 'lock_test_support.dart';

/// The dashboard lists only the leading salespersons, however many there are.
/// The full rankings live on People (by balance) and Reports (by goods taken),
/// so the short list on Home hides nothing.
void main() {
  testWidgets('Home shows only the top 3, in order, however many exist',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    await repo.seedDemoData();

    // The demo shop has six salespersons, all with sales this month.
    final ledger = await repo.loadLedger();
    final ranked = ledger.topSalespersons(Period.thisMonth(DateTime.now()));
    expect(ledger.salespersons.length, 6);
    expect(ranked.length, greaterThan(3), reason: 'more than the cap');

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();

    // The three biggest takers are listed…
    for (final e in ranked.take(3)) {
      expect(find.text(e.key.name), findsWidgets, reason: e.key.name);
    }
    // …and the rest are not on the dashboard at all.
    for (final e in ranked.skip(3)) {
      expect(find.text(e.key.name), findsNothing, reason: e.key.name);
    }
  });

  testWidgets('"See all" opens the People tab, where everyone is listed',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).seedDemoData();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();

    // Someone outside the dashboard's top three.
    expect(find.text('Bilal Ahmed'), findsNothing);

    await tester.tap(find.byKey(seeAllSalespersonsKey));
    await tester.pumpAndSettle();

    // The People tab is now showing, with the whole roster.
    expect(find.text('Search staff'), findsOneWidget);
    expect(find.text('Bilal Ahmed'), findsWidgets);
  });

  testWidgets('a shop with fewer than three shows just those it has',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // Appendix A has three salespersons, all with sales.
    await StoreRepository(db).resetToSampleData();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();

    for (final name in ['Rahul', 'Amir', 'Sana']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
  });
}
