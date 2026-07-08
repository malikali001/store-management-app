import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store_manager/app/providers.dart';
import 'lock_test_support.dart';
import 'package:store_manager/data/database.dart';
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/main.dart';

/// Boots the real app against an in-memory DB seeded with Appendix A and
/// verifies the running dashboard reproduces the golden numbers (acceptance
/// criterion: "All Appendix A numbers reproduced ... by the running app's
/// dashboard").
void main() {
  testWidgets('Home dashboard shows Appendix A figures', (tester) async {
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

    // Cash on hand 65,300; Stock value 76,900; Owed 13,600.
    expect(find.text('65,300'), findsWidgets);
    expect(find.text('76,900'), findsWidgets);
    expect(find.text('13,600'), findsWidgets);

    // Period defaults to Month → net profit this month 1,890.
    expect(find.text('1,890'), findsWidgets);
  });
}
