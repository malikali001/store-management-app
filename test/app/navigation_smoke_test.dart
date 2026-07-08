import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'lock_test_support.dart';
import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';

/// Smoke test: boots the app and exercises pushed routes and a form sheet to
/// ensure they build at runtime without throwing.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
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

  testWidgets('Settings screen opens from the gear', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Clear all data'), findsWidgets);
  });

  testWidgets('New sale sheet opens from Home quick action', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await pumpApp(tester);

    final action = find.text('New sale').first;
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    // "Save sale" exists only inside the opened sale sheet.
    expect(find.text('Save sale'), findsOneWidget);
  });

  testWidgets('Salesperson ledger opens from People tab', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    // People leads with the Shops segment; switch to Staff for salespersons.
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    // Tap the first salesperson row (seeded data has Rahul/Amir/Sana).
    await tester.tap(find.text('Amir').first);
    await tester.pumpAndSettle();
    // Ledger shows a "Record payment" action.
    expect(find.text('Record payment'), findsWidgets);
  });
}
