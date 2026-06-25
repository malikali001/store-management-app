import 'package:flutter/material.dart';
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
import 'services/backup.dart';
import 'services/backup_status.dart';
import 'sheets/recurring_expense_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  // Populate a realistic starter dataset on first run.
  await StoreRepository(db).seedIfEmpty();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const StoreManagerApp(),
    ),
  );
}

class StoreManagerApp extends StatelessWidget {
  const StoreManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Store Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootShell(),
    );
  }
}

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

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
      backgroundColor: const Color(0xFFFBF1DC),
      leading: const Icon(Icons.shield_outlined, color: AppColors.warning),
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
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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
