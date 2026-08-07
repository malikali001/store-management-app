import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'screens/home_screen.dart';
import 'screens/products_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/people_screen.dart';
import 'screens/reports_screen.dart';
import 'security/lock_gate.dart';
import 'services/backup.dart';
import 'services/backup_status.dart';
import 'sheets/recurring_expense_sheet.dart';

/// How long startup waits for the local database to become usable before giving
/// up and showing the startup error screen. Generous enough for a cold wasm/OPFS
/// open on a slow device, short enough that the user is never left staring at a
/// blank screen.
const startupDatabaseTimeout = Duration(seconds: 20);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The receipt PDF embeds Roboto (Apache 2.0); surface its licence in the
  // app's "Licenses" page as the licence requires.
  LicenseRegistry.addLicense(() async* {
    final license =
        await rootBundle.loadString('assets/fonts/Roboto-LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['Roboto'], license);
  });

  AppDatabase db;
  try {
    db = AppDatabase();
    // Ensure sensible default settings exist on first run.
    //
    // The timeout matters as much as the try/catch: opening the database can
    // *stall* rather than fail (on web the wasm worker handshake can hang), and
    // without a deadline `runApp` would never be reached — leaving a blank white
    // screen with nothing to explain it. Bounding it turns a hang into the same
    // plain-language error screen as an outright failure.
    await StoreRepository(db).seedIfEmpty().timeout(startupDatabaseTimeout);
  } catch (e) {
    // The local database could not be opened or took too long (e.g. a corrupt
    // file on native, or missing/stalled sqlite worker assets on web). Show a
    // plain-language screen rather than a silent blank page.
    runApp(const _StartupErrorApp());
    return;
  }

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const StoreManagerApp(),
    ),
  );
}

/// Shown when the app cannot open its local database at startup.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                const Text(
                  'Store Manager could not open its data on this device. '
                  'Please restart the app. If this keeps happening, reinstall '
                  'and restore from your most recent backup.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StoreManagerApp extends StatelessWidget {
  const StoreManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Store Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LockGate(child: RootShell()),
    );
  }
}

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  static const _tabs = [
    HomeScreen(),
    ProductsScreen(),
    SalesScreen(),
    PeopleScreen(),
    ReportsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Offer this month's recurring expenses if due.
      await maybeShowRecurringPrompt(context, ref);
      // Then nudge to back up if the data hasn't left the device recently.
      if (mounted) _maybeNudgeBackup();
    });
  }

  Future<void> _maybeNudgeBackup() async {
    final status = await ref.read(backupStatusProvider.future);
    if (!mounted || !status.isStale) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(MaterialBanner(
      backgroundColor: AppColors.warnSurface,
      leading: Icon(Icons.shield_outlined, color: AppColors.warning),
      content: Text(status.lastBackup == null
          ? 'Your data is only on this phone. Back it up so a lost or changed '
              'phone never means lost records.'
          : 'It has been a while since your last backup. Back up to stay safe.'),
      actions: [
        TextButton(
          onPressed: () => messenger.hideCurrentMaterialBanner(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            backupToFile(context, ref);
          },
          child: const Text('Back up now'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    // The selected tab lives in a provider so other screens can navigate here
    // (see [selectedTabProvider]).
    final index = ref.watch(selectedTabProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => ref.read(selectedTabProvider.notifier).state = i,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Products'),
          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_outlined), activeIcon: Icon(Icons.point_of_sale), label: 'Sales'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'People'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }
}
