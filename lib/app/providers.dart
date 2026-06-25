import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
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

/// Period selector for Home / Reports.
final periodKindProvider = StateProvider<PeriodKind>((ref) => PeriodKind.month);

/// The active [Period], resolved against the device-local clock.
final periodProvider = Provider<Period>((ref) {
  final kind = ref.watch(periodKindProvider);
  return Period.forKind(kind, DateTime.now());
});

/// App theme mode (system / light / dark), persisted in the settings table
/// under 'theme_mode'. It is a device UI preference, not store data, so it lives
/// outside [StoreSettings] and the backup payload.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final raw = await ref.read(repositoryProvider).rawSetting('theme_mode');
    final mode = _parse(raw);
    if (mode != state) state = mode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(repositoryProvider).setSetting('theme_mode', mode.name);
  }

  static ThemeMode _parse(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Managed dropdown values for a list kind ('brand','category','size',
/// 'expense_category').
final listValuesProvider =
    FutureProvider.family<List<String>, String>((ref, kind) async {
  // Re-fetch when the ledger changes (lists may have grown).
  ref.watch(ledgerProvider);
  return ref.watch(repositoryProvider).listValues(kind);
});
