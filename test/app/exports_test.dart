import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/screens/settings_screen.dart';
import 'package:store_manager/services/report_pdf.dart';

import 'lock_test_support.dart';

/// Exercises the report / CSV / backup UI flows. The OS share, print and
/// file-picker plugins are absent under `flutter test`, so those calls throw
/// and the app handles them gracefully — but the build logic (PDF, CSV rows,
/// backup JSON, progress dialog) all runs and gets covered.
void main() {
  // Reports build inline so pumpAndSettle can drive them (no background isolate).
  debugBuildReportsInline = true;

  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<AppDatabase> pumpFullApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          lockTestOverride(),
        ],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  Future<Widget> settingsApp(AppDatabase db) async => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          lockTestOverride(),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      );

  testWidgets('Reports: generate all three PDF reports and all CSV exports',
      (tester) async {
    bigSurface(tester);
    await pumpFullApp(tester);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    for (final label in const [
      'Products & inventory',
      'Shops (customers)',
      'Salespersons',
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      // The generate flow ran and cleaned up (no lingering progress dialog).
      expect(find.text('Generating report…'), findsNothing);
    }

    for (final label in const ['Products', 'People', 'Transactions']) {
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await tester.pumpAndSettle();
      expect(find.text('Preparing CSV…'), findsNothing);
    }
    // Still on the Reports screen — nothing crashed.
    expect(find.text('Download report (PDF)'), findsOneWidget);
  });

  testWidgets('Settings: backup flow builds the file (no password)',
      (tester) async {
    bigSurface(tester);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData();
    await tester.pumpWidget(await settingsApp(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back up everything'));
    await tester.pumpAndSettle();
    // The password dialog appears; back up without a password.
    expect(find.text('Protect this backup'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Back up'));
    await tester.pumpAndSettle();
    // Progress dialog cleaned up; still on Settings.
    expect(find.text('Preparing backup…'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Settings: clear-all requires typing the store name',
      (tester) async {
    bigSurface(tester);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).resetToSampleData();
    final storeName = (await StoreRepository(db).loadLedger()).settings.storeName;
    await tester.pumpWidget(await settingsApp(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear all data'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all data'), findsWidgets);

    // Type the store name to enable the destructive button, then confirm.
    await tester.enterText(find.byType(TextField).last, storeName);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear everything'));
    await tester.pumpAndSettle();

    final ledger = await StoreRepository(db).loadLedger();
    expect(ledger.products, isEmpty);
    expect(ledger.txns, isEmpty);
  });
}
