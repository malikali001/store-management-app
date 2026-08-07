import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../domain/product_insights.dart';
import '../domain/shop_insights.dart';
import 'format.dart';

/// The Drift database. Overridden in main() after it is opened & seeded.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

final repositoryProvider = Provider<StoreRepository>((ref) {
  return StoreRepository(ref.watch(databaseProvider));
});

/// The reactive ledger — re-derived whenever any table changes.
final ledgerProvider = StreamProvider<Ledger>((ref) {
  return ref.watch(repositoryProvider).watchLedger();
});

/// Convenience: the current settings (or defaults while loading).
final settingsProvider = Provider<StoreSettings>((ref) {
  return ref.watch(ledgerProvider).maybeWhen(
        data: (l) => l.settings,
        orElse: () => const StoreSettings(),
      );
});

/// Money formatter bound to current settings.
final moneyProvider = Provider<Money>((ref) {
  return Money(ref.watch(settingsProvider));
});

/// Bottom-nav tab indices (Section 7), named so cross-tab navigation reads
/// clearly instead of using bare integers.
abstract final class AppTab {
  static const home = 0;
  static const products = 1;
  static const sales = 2;
  static const people = 3;
  static const reports = 4;
}

/// The selected bottom-nav tab. Held in a provider rather than in the shell's
/// own state so one screen can send the user to another tab — Home's "See all"
/// on Top salespersons opens People.
final selectedTabProvider = StateProvider<int>((ref) => AppTab.home);

/// Period selector for Home / Reports.
final periodKindProvider = StateProvider<PeriodKind>((ref) => PeriodKind.month);

/// The active [Period], resolved against the device-local clock.
final periodProvider = Provider<Period>((ref) {
  final kind = ref.watch(periodKindProvider);
  return Period.forKind(kind, DateTime.now());
});

/// Product performance insights for the active period (Home + the insights
/// screen). Derived in one pass over the ledger and shared by both, so the
/// widgets never do the math themselves.
final productInsightsProvider = Provider<AsyncValue<ProductInsights>>((ref) {
  final period = ref.watch(periodProvider);
  return ref
      .watch(ledgerProvider)
      .whenData((l) => ProductInsights.build(l, period, DateTime.now()));
});

/// Customer (shop) performance insights for the active period. Shares the same
/// shape as [productInsightsProvider]; both keep the math out of the widgets.
final shopInsightsProvider = Provider<AsyncValue<ShopInsights>>((ref) {
  final period = ref.watch(periodProvider);
  final now = DateTime.now();
  return ref
      .watch(ledgerProvider)
      .whenData((l) => ShopInsights.build(l, period, now));
});

/// Managed dropdown values for a list kind ('brand','category','size',
/// 'expense_category').
final listValuesProvider =
    FutureProvider.family<List<String>, String>((ref, kind) async {
  // Re-fetch when the ledger changes (lists may have grown).
  ref.watch(ledgerProvider);
  return ref.watch(repositoryProvider).listValues(kind);
});
