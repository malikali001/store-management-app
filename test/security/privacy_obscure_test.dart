import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';
import 'package:store_manager/security/lock_gate.dart';
import '../app/lock_test_support.dart';

/// The privacy overlay hides the ledger in the OS app switcher. It must never
/// blank the app while the user is still looking at it.
///
/// Regression: the overlay used to appear for *any* lifecycle state other than
/// `resumed`, and regardless of whether the lock was even switched on. On the
/// web an unfocused tab reports `inactive`, so clicking to another window
/// covered the whole app with an opaque box — indistinguishable from a crash.
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await StoreRepository(db).seedDemoData();

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), lockTestOverride()],
      child: const StoreManagerApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState st) async {
    tester.binding.handleAppLifecycleStateChanged(st);
    await tester.pumpAndSettle();
  }

  /// The transitions Flutter actually delivers: out to the background and back.
  /// (The framework asserts on shortcuts like paused → resumed.)
  const backgroundAndReturn = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('with the lock off, no lifecycle state ever blanks the app',
      (tester) async {
    await pumpApp(tester);
    expect(find.byKey(privacyObscureKey), findsNothing);

    for (final st in backgroundAndReturn) {
      await lifecycle(tester, st);
      expect(find.byKey(privacyObscureKey), findsNothing,
          reason: 'lock is off, so $st must not obscure the app');
      // The dashboard is still there and readable.
      expect(find.text('Malik'), findsWidgets, reason: 'after $st');
    }
  });

  testWidgets('losing focus alone does not obscure, even with the lock on',
      (tester) async {
    await pumpApp(tester);

    // `inactive` is the state an unfocused window/tab reports — the user is
    // still looking at the app, so it must stay visible.
    await lifecycle(tester, AppLifecycleState.inactive);
    expect(find.byKey(privacyObscureKey), findsNothing);
    expect(find.text('Malik'), findsWidgets);

    // Coming back is a no-op rather than a flash.
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(find.byKey(privacyObscureKey), findsNothing);
  });

  testWidgets('returning to the foreground always clears the overlay',
      (tester) async {
    await pumpApp(tester);
    for (final st in backgroundAndReturn) {
      await lifecycle(tester, st);
    }
    expect(find.byKey(privacyObscureKey), findsNothing);
    expect(find.text('Malik'), findsWidgets);
  });
}
