import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../sheets/salesperson_form.dart';
import 'salesperson_ledger_screen.dart';

/// Section 7.9 — people (salespersons).
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Add person',
            icon: const Icon(Icons.add),
            onPressed: () => showSalespersonForm(context, ref),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildBody(context, ref, ledger),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Ledger ledger) {
    final money = ref.watch(moneyProvider);
    final people = ledger.salespersons
        .where((s) => !s.archived)
        .toList()
      ..sort((a, b) => ledger.balance(b.id).compareTo(ledger.balance(a.id)));

    if (people.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        message: 'No salespersons yet. Tap + to add one.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = people[i];
        final bal = ledger.balance(s.id);
        return AppCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SalespersonLedgerScreen(salespersonId: s.id),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(s.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text(money.format(bal),
                  style: tabularFigures.copyWith(
                    fontWeight: FontWeight.w600,
                    color: bal > 0 ? AppColors.danger : AppColors.ink,
                  )),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        );
      },
    );
  }
}
