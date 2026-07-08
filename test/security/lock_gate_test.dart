import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/main.dart';
import 'package:store_manager/security/lock_controller.dart';
import 'package:store_manager/security/lock_service.dart';

import '../app/lock_test_support.dart';

void main() {
  testWidgets('lock gate blocks the app until the correct PIN is entered',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // A lock is configured and switched on.
    final service = LockService(store: FakeSecureStore());
    await service.setPin('1234');
    expect(await service.isEnabled(), isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          lockServiceProvider.overrideWithValue(service),
        ],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The lock screen is shown; the home tabs are not reachable.
    expect(find.text('Enter your PIN'), findsOneWidget);

    // Wrong PIN keeps it locked.
    for (final d in ['9', '9', '9', '9']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Enter your PIN'), findsOneWidget);

    // Correct PIN unlocks and reveals the app.
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('Products'), findsWidgets); // bottom nav is present
  });

  testWidgets('Forgot PIN? → recovery code resets the PIN and unlocks',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final service = LockService(store: FakeSecureStore());
    await service.setPin('1234');
    final code = service.generateRecoveryCode();
    await service.setRecoveryCode(code);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          lockServiceProvider.overrideWithValue(service),
        ],
        child: const StoreManagerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);

    // Open the recovery flow.
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your PIN'), findsOneWidget);

    // Fill recovery code, new PIN, confirm — the three fields in order.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), code);
    await tester.enterText(fields.at(1), '5678');
    await tester.enterText(fields.at(2), '5678');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset PIN'));
    await tester.pumpAndSettle();

    // Unlocked, and the new PIN is what now verifies.
    expect(find.text('Enter your PIN'), findsNothing);
    expect(await service.verifyPin('5678'), PinResult.ok);
  });
}
