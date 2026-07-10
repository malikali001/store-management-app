import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/security/lock_controller.dart';
import 'package:store_manager/screens/settings_screen.dart';

import 'lock_test_support.dart';

/// Drives the Settings → Security section end to end with a synchronous
/// (isolate-free) lock service: turn on the lock (recovery code shown), set the
/// auto-lock delay, reset the recovery code, change the PIN, and turn it off.
void main() {
  void bigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('turn on lock, set auto-lock, reset recovery, change PIN, off',
      (tester) async {
    bigSurface(tester);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final lock = fakeLockService();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        lockServiceProvider.overrideWithValue(lock),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    // Turn the lock on.
    await tester.ensureVisible(find.text('Turn on app lock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn on app lock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new_pin')), '2468');
    await tester.enterText(find.byKey(const Key('confirm_pin')), '2468');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    // Recovery code is shown; confirm it's saved.
    expect(find.text('Your recovery code'), findsOneWidget);
    await tester.tap(find.text('I have saved it'));
    await tester.pumpAndSettle();
    expect(await lock.isEnabled(), isTrue);
    expect(await lock.hasRecoveryCode(), isTrue);

    // Set auto-lock to 5 minutes.
    await tester.ensureVisible(find.text('After 5 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After 5 min'));
    await tester.pumpAndSettle();
    expect(await lock.autoLockMinutes(), 5);

    // Reset the recovery code (requires the current PIN).
    await tester.ensureVisible(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('current_pin')), '2468');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your recovery code'), findsOneWidget);
    await tester.tap(find.text('I have saved it'));
    await tester.pumpAndSettle();

    // Change the PIN (requires the current PIN, then a new one).
    await tester.ensureVisible(find.text('Change PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('current_pin')), '2468');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new_pin')), '1357');
    await tester.enterText(find.byKey(const Key('confirm_pin')), '1357');
    await tester.tap(find.text('Save PIN'));
    await tester.pumpAndSettle();

    // Turn the lock off (requires the current, now-changed PIN).
    await tester.ensureVisible(find.text('Turn off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('current_pin')), '1357');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await lock.isEnabled(), isFalse);
  });
}
