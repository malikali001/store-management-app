import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../sheets/entry_detail_sheet.dart';
import '../sheets/payment_sheet.dart';
import '../sheets/sale_sheet.dart';
import '../sheets/salesperson_form.dart';
import '../services/receipt.dart';

/// Section 7.10 — a single salesperson's ledger.
class SalespersonLedgerScreen extends ConsumerWidget {
  final String salespersonId;
  const SalespersonLedgerScreen({super.key, required this.salespersonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ledgerAsync.maybeWhen(
          data: (l) =>
              l.salesperson(salespersonId)?.name ?? '(former salesperson)',
          orElse: () => '',
        )),
        actions: [
          if (ledgerAsync.valueOrNull?.salesperson(salespersonId) != null)
            IconButton(
              tooltip: 'Edit salesperson',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showSalespersonForm(context, ref,
                  existing: ledgerAsync.value!.salesperson(salespersonId)),
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
    final balance = ledger.balance(salespersonId);
    final exists = ledger.salesperson(salespersonId) != null;

    final history = ledger.txns
        .where((t) =>
            t.salespersonId == salespersonId &&
            (t.type == TxnType.sale ||
                t.type == TxnType.returnGoods ||
                t.type == TxnType.payment))
        .toList()
      ..sort((a, b) => Txn.compare(b, a));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current balance owed',
                    style:
                        TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text(money.format(balance),
                    style: tabularFigures.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      color: balance > 0 ? AppColors.danger : AppColors.ink,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => showPaymentSheet(context, ref,
                      salespersonId: salespersonId),
                  child: const Text('Record payment'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      showSaleSheet(context, ref, salespersonId: salespersonId),
                  child: const Text('New sale'),
                ),
              ),
            ],
          ),
          const SectionTitle('History'),
          if (history.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No activity yet',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < history.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _HistoryRow(
                      txn: history[i],
                      money: money,
                      onTap: () {
                        if (history[i].type == TxnType.sale) {
                          showReceiptSheet(context, ref, history[i].id);
                        } else {
                          showEntryDetail(context, ref, history[i]);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: Icon(Icons.person_remove_outlined,
                color: AppColors.danger),
            label: Text('Remove salesperson',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: AppColors.danger),
            ),
            onPressed: exists
                ? () => _remove(context, ref)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Remove salesperson',
      message:
          'This keeps their history but removes them from your lists. Continue?',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteSalesperson(salespersonId);
      if (!context.mounted) return;
      showToast(context, 'Salesperson removed');
      Navigator.of(context).pop();
    } on DomainError catch (e) {
      if (!context.mounted) return;
      showError(context, e.message);
    } catch (e) {
      if (!context.mounted) return;
      showError(context, 'Could not remove: $e');
    }
  }
}

class _HistoryRow extends StatelessWidget {
  final Txn txn;
  final Money money;
  final VoidCallback onTap;
  const _HistoryRow(
      {required this.txn, required this.money, required this.onTap});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final int signedAmount; // positive raises balance
    switch (txn.type) {
      case TxnType.sale:
        label = 'Took goods';
        signedAmount = txn.linesSell;
        break;
      case TxnType.returnGoods:
        label = 'Returned goods';
        signedAmount = -txn.linesSell;
        break;
      case TxnType.payment:
        label = 'Payment received';
        signedAmount = -(txn.amount ?? 0);
        break;
      default:
        label = '';
        signedAmount = 0;
    }
    final isCredit = signedAmount < 0;
    final text = (isCredit ? '−' : '+') + money.format(signedAmount.abs());

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(prettyDate(txn.date),
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text(text,
                style: tabularFigures.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isCredit ? AppColors.positive : AppColors.ink,
                )),
          ],
        ),
      ),
    );
  }
}
