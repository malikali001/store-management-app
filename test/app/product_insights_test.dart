import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/product_insights.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/screens/home_screen.dart' show seeAllProductsKey;
import 'package:store_manager/screens/product_detail_screen.dart';
import 'package:store_manager/screens/product_insights_screen.dart';
import 'lock_test_support.dart';

/// Boots the real app against an in-memory DB seeded with Appendix A and drives
/// the product-insights feature end to end: the Home headlines, the full
/// insights screen, switching lenses, and tapping through to a product.
void main() {
  Future<void> boot(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Home carries several "See all" links; name the one we mean.
  final productsSeeAll = find.byKey(seeAllProductsKey);

  /// Scrolls the dashboard down to the insights card.
  Future<void> scrollToInsights(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Product insights'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home shows a product-insights headline per lens', (tester) async {
    await boot(tester);
    await scrollToInsights(tester);

    // Four lenses, four different products (see the domain test for the ranks).
    expect(find.text('Fast mover'), findsOneWidget);
    expect(find.text('Most profit'), findsOneWidget);
    expect(find.text('Restock soon'), findsOneWidget);
    expect(find.text('Trending up'), findsOneWidget);

    // Cotton tee · M moved 40 units — the fast mover.
    expect(find.text('Cotton tee · M'), findsOneWidget);
    expect(find.text('40 units'), findsOneWidget);
    // Runner shoe · 7 earned the most margin: 10 × (1200 − 900) = 3,000.
    expect(find.text('Runner shoe · 7'), findsOneWidget);
    expect(find.text('3,000'), findsWidgets);
  });

  testWidgets('tapping a headline opens that lens, and lenses switch',
      (tester) async {
    await boot(tester);
    await scrollToInsights(tester);

    await tester.tap(find.text('Cotton tee · M'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductInsightsScreen), findsOneWidget);

    // Landed on "Fast movers": five products sold, ranked by units.
    expect(find.text('Most units sold in this period.'), findsOneWidget);
    expect(find.text('40 units'), findsWidgets);
    expect(find.text('10,000 in sales'), findsOneWidget); // TS-M revenue

    // Switch to the margin lens — CP-S keeps 40% of every sale.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Best margin'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('2,400 on 6,000 of sales'), findsOneWidget);

    // And to the restock lens — TS-M has the least cover, 1.5 days.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Restock soon'));
    await tester.pumpAndSettle();
    expect(find.text('60 left · 40 units sold'), findsOneWidget);
    expect(find.text('2 days'), findsWidgets);
  });

  testWidgets('an insight row opens that product', (tester) async {
    await boot(tester);
    await scrollToInsights(tester);
    await tester.tap(productsSeeAll);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cotton tee · M'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.text('Movement history'), findsOneWidget);
  });

  testWidgets('every lens lays out on a narrow screen at 2x text scale',
      (tester) async {
    // Accessibility (Section 14): the app must survive OS text scaling. Any
    // RenderFlex overflow while laying out these rows fails the test.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData();
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: StoreManagerApp(),
      ),
    ));
    await tester.pumpAndSettle();

    await scrollToInsights(tester);
    await tester.ensureVisible(productsSeeAll);
    await tester.pumpAndSettle();
    await tester.tap(productsSeeAll);
    await tester.pumpAndSettle();
    expect(find.byType(ProductInsightsScreen), findsOneWidget);

    for (final lens in InsightLens.values) {
      final chip = find.widgetWithText(ChoiceChip, lens.title);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      // Scroll the whole ranked list so every row actually gets laid out.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an empty catalog says so instead of ranking nothing',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).seedIfEmpty(); // settings only, no products

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToInsights(tester);

    expect(find.text('Record a sale to see which products earn the most.'),
        findsOneWidget);
  });
}
