import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/period_selector.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../sheets/entry_detail_sheet.dart';
import '../services/csv_export.dart';

/// Section 7.11 — reports.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reports')),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildBody(context, ref, ledger),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Ledger ledger) {
    final money = ref.watch(moneyProvider);
    final period = ref.watch(periodProvider);

    var goodsTaken = 0;
    var goodsReturned = 0;
    var moneyCollected = 0;
    final expenseByCat = <String, int>{};
    final recentExpenses = <Txn>[];

    for (final t in ledger.txns) {
      if (!period.contains(t.date)) continue;
      switch (t.type) {
        case TxnType.sale:
          goodsTaken += t.linesSell;
          break;
        case TxnType.returnGoods:
          goodsReturned += t.linesSell;
          break;
        case TxnType.payment:
          moneyCollected += t.amount ?? 0;
          break;
        case TxnType.expense:
          final cat = (t.category ?? '').isEmpty ? 'Uncategorised' : t.category!;
          expenseByCat[cat] = (expenseByCat[cat] ?? 0) + (t.amount ?? 0);
          recentExpenses.add(t);
          break;
        default:
          break;
      }
    }
    recentExpenses.sort((a, b) => Txn.compare(b, a));

    final grossProfit = ledger.recognisedProfitInPeriod(period);
    final expenses = ledger.expensesInPeriod(period);
    final netProfit = ledger.netProfitInPeriod(period);
    final top = ledger.topSalespersons(period);

    final catEntries = expenseByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PeriodSelector(),
          SectionTitle('Money · ${_periodLabel(period.kind)}'),
          AppCard(
            child: Column(
              children: [
                _MoneyRow('Goods taken', money.format(goodsTaken)),
                _MoneyRow('Goods returned', money.format(goodsReturned)),
                _MoneyRow('Money collected', money.format(moneyCollected)),
                _MoneyRow('Recognised profit', money.format(grossProfit),
                    color: AppColors.positive),
                _MoneyRow('Expenses', money.format(expenses),
                    color: AppColors.danger),
                const Divider(height: 16),
                _MoneyRow('Net profit', money.format(netProfit),
                    bold: true,
                    color:
                        netProfit < 0 ? AppColors.danger : AppColors.positive),
              ],
            ),
          ),
          const SectionTitle('Expenses by category'),
          if (catEntries.isEmpty)
            const _MutedCard('No expenses in this period')
          else
            AppCard(
              child: Column(
                children: [
                  for (final e in catEntries)
                    _MoneyRow(e.key, money.format(e.value)),
                ],
              ),
            ),
          const SectionTitle('Recent expenses'),
          if (recentExpenses.isEmpty)
            const _MutedCard('No expenses in this period')
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0;
                      i < recentExpenses.length && i < 8;
                      i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text((recentExpenses[i].category ?? '').isEmpty
                          ? 'Uncategorised'
                          : recentExpenses[i].category!),
                      subtitle: Text(prettyDate(recentExpenses[i].date)),
                      trailing: Text(
                          money.format(recentExpenses[i].amount ?? 0),
                          style: tabularFigures.copyWith(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w500)),
                      onTap: () =>
                          showEntryDetail(context, ref, recentExpenses[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SectionTitle('Who sells more'),
          if (top.isEmpty)
            const _MutedCard('No sales in this period')
          else
            AppCard(
              child: Column(
                children: [
                  for (final e in top)
                    _MoneyRow(e.key.name, money.format(e.value)),
                ],
              ),
            ),
          const SectionTitle('Export'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => exportProductsCsv(context, ref),
                  child: const Text('Products'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => exportSalespersonsCsv(context, ref),
                  child: const Text('People'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => exportTransactionsCsv(context, ref),
                  child: const Text('Transactions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _periodLabel(PeriodKind kind) =>
      PeriodSelector.label(kind).toLowerCase();
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _MoneyRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w700 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: weight,
                    color: bold ? AppColors.ink : AppColors.ink)),
          ),
          Text(value,
              style: tabularFigures.copyWith(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? AppColors.ink)),
        ],
      ),
    );
  }
}

class _MutedCard extends StatelessWidget {
  final String message;
  const _MutedCard(this.message);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(message, style: TextStyle(color: AppColors.muted)),
      ),
    );
  }
}
