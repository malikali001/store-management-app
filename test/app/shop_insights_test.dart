import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' show AppDatabase;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/models.dart' show Shop;
import 'package:store_manager/domain/shop_insights.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/screens/home_screen.dart' show seeAllCustomersKey;
import 'package:store_manager/screens/shop_detail_screen.dart';
import 'package:store_manager/screens/shop_insights_screen.dart';
import 'package:store_manager/screens/shops_screen.dart';
import 'lock_test_support.dart';

/// Drives the customer (shops) feature against the demo dataset — which has a
/// deliberate spread of buying behaviours — through the real app: the Customers
/// section on the dashboard, the Shops page it opens, the insights screen, lens
/// switching, and tap-through to a shop.
void main() {
  /// Boots the app on the demo dataset, landing on Home.
  Future<AppDatabase> bootHome(WidgetTester tester,
      {double textScale = 1.0}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).seedDemoData();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const StoreManagerApp(),
      ),
    ));
    await tester.pumpAndSettle();
    return db;
  }

  /// Scrolls the dashboard down to its Customers section.
  Future<void> scrollToCustomers(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Customers'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Home → Customers → "See all", which opens the Shops page.
  Future<void> goShops(WidgetTester tester) async {
    await scrollToCustomers(tester);
    final seeAll = find.byKey(seeAllCustomersKey);
    await tester.ensureVisible(seeAll);
    await tester.pumpAndSettle();
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.byType(ShopsScreen), findsOneWidget);
  }

  /// From the Shops page, open the full insights screen via its app-bar action.
  Future<void> goInsights(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ShopInsightsScreen), findsOneWidget);
  }

  testWidgets('the dashboard reports customer figures and opens the Shops page',
      (tester) async {
    await bootHome(tester);
    await scrollToCustomers(tester);

    // Five demo customers, 480,000 bought between them all-time.
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('Rs 480,000'), findsOneWidget);
    // Old Bazaar Supplies has lapsed, so the warning chip appears.
    expect(find.text('Gone quiet · 1'), findsOneWidget);
    // Headline rows are on the dashboard too.
    expect(find.text('Top buyer'), findsOneWidget);
    expect(find.text('Metro Mart'), findsWidgets);

    await goShops(tester);
    expect(find.text('Shops'), findsWidgets);
    expect(find.text('Metro Mart'), findsWidgets);
  });

  testWidgets('the People tab no longer carries shops', (tester) async {
    await bootHome(tester);
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();

    // Salespersons only — no Shops/Staff switch, and no customer shops.
    expect(find.text('Staff'), findsNothing);
    expect(find.text('Metro Mart'), findsNothing);
    // …just the salespersons, ranked by what they owe.
    expect(find.text('Amir Khan'), findsWidgets);
    expect(find.text('Search staff'), findsOneWidget);
  });

  testWidgets('the Shops page leads with insight headlines', (tester) async {
    await bootHome(tester);
    await goShops(tester);

    expect(find.text('Insights'), findsOneWidget);
    // Twice: the headline row's label, and the "Top buyer" badge on Metro
    // Mart's own card further down the list.
    expect(find.text('Top buyer'), findsNWidgets(2));
  });

  testWidgets('insights rank buyers and switch lenses', (tester) async {
    await bootHome(tester);
    await goShops(tester);
    await goInsights(tester);

    // Default lens: top buyers for the period.
    expect(find.text('Spent the most in this period.'), findsOneWidget);

    // All time makes the full relationship visible.
    await tester.tap(find.widgetWithText(ChoiceChip, 'All time'));
    await tester.pumpAndSettle();
    expect(find.text('Metro Mart'), findsOneWidget);
    expect(find.text('Rs 338,000'), findsOneWidget); // 7 orders, all-time

    // "Gone quiet" surfaces the lapsed customer and nobody else.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Gone quiet'));
    await tester.pumpAndSettle();
    expect(find.text('Old Bazaar Supplies'), findsOneWidget);
    expect(find.text('130 days'), findsOneWidget);
    expect(find.text('Metro Mart'), findsNothing);

    // Biggest orders is about average value, not total spend.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Biggest orders'));
    await tester.pumpAndSettle();
    expect(find.text('Rs 48,286'), findsOneWidget); // 338,000 / 7
  });

  testWidgets('a customer with no orders yet is reported as such',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    await repo.seedDemoData();
    // A shop on the books that has never ordered.
    await repo.upsertShop(Shop(
      id: 'shop_new',
      name: 'Untouched Traders',
      createdAt: DateTime.now()
          .subtract(const Duration(days: 40))
          .millisecondsSinceEpoch,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();
    await goShops(tester);
    await goInsights(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Never bought'));
    await tester.pumpAndSettle();
    expect(find.text('Untouched Traders'), findsOneWidget);
    expect(find.text('40 days'), findsOneWidget);
  });

  testWidgets('an insight row opens that shop', (tester) async {
    await bootHome(tester);
    await goShops(tester);
    await goInsights(tester);

    await tester.tap(find.text('Metro Mart').first);
    await tester.pumpAndSettle();
    expect(find.byType(ShopDetailScreen), findsOneWidget);
    expect(find.text('Purchase history'), findsOneWidget);
  });

  testWidgets('searching hides the insights header so results lead',
      (tester) async {
    await bootHome(tester);
    await goShops(tester);
    expect(find.text('Insights'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hilltop');
    await tester.pumpAndSettle();
    expect(find.text('Insights'), findsNothing);
    expect(find.text('Hilltop Traders'), findsOneWidget);
  });

  testWidgets('every lens lays out on a narrow screen at 2x text scale',
      (tester) async {
    // Narrow, but tall enough to reach the dashboard's Customers section and
    // page through without the viewport itself being the constraint.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await bootHome(tester, textScale: 2.0);
    await goShops(tester);
    await goInsights(tester);

    for (final lens in ShopLens.values) {
      final chip = find.widgetWithText(ChoiceChip, lens.title);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
    }
  });
}
