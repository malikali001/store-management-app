import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../sheets/salesperson_form.dart';
import 'salesperson_ledger_screen.dart';

/// Section 7.9 — people: the hired staff (salespersons) who take goods on
/// credit, sorted by balance owed.
///
/// Customer shops are a different relationship entirely and live on their own
/// page, reached from the Customers section on Home.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Add salesperson',
            icon: const Icon(Icons.add),
            onPressed: () => showSalespersonForm(context, ref),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildList(ledger),
      ),
    );
  }

  Widget _buildList(Ledger ledger) {
    final money = ref.watch(moneyProvider);

    final all = ledger.salespersons.where((s) => !s.archived).toList();
    final q = _query.trim().toLowerCase();
    var people = all;
    if (q.isNotEmpty) {
      people = all
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.phone.toLowerCase().contains(q))
          .toList();
    }
    people.sort((a, b) => ledger.balance(b.id).compareTo(ledger.balance(a.id)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search staff',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: people.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  message: all.isEmpty
                      ? 'No salespersons yet. Tap + to add one.'
                      : 'No staff match your search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = people[i];
                    final bal = ledger.balance(s.id);
                    return AppCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SalespersonLedgerScreen(salespersonId: s.id),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(s.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ),
                          const SizedBox(width: 8),
                          // Flexible so a large OS text scale wraps the amount
                          // rather than overflowing the card.
                          Flexible(
                            flex: 2,
                            child: Text(money.format(bal),
                                textAlign: TextAlign.end,
                                style: tabularFigures.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: bal > 0
                                      ? AppColors.danger
                                      : AppColors.ink,
                                )),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
