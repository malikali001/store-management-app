import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../sheets/entry_detail_sheet.dart';
import '../sheets/payment_sheet.dart';
import '../sheets/return_sheet.dart';
import '../sheets/sale_sheet.dart';
import '../services/receipt.dart';

/// Section 7.4 — sales & payments.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Sales')),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildBody(context, ref, ledger),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Ledger ledger) {
    final money = ref.watch(moneyProvider);

    final entries = ledger.txns
        .where((t) =>
            t.type == TxnType.sale || t.type == TxnType.returnGoods)
        .toList()
      ..sort((a, b) => Txn.compare(b, a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => showSaleSheet(context, ref),
                  child: const Text('New sale'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showPaymentSheet(context, ref),
                  child: const Text('Record payment'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showReturnSheet(context, ref),
                  child: const Text('Return goods'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(
                  icon: Icons.point_of_sale_outlined,
                  message: 'No sales or returns yet.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = entries[i];
                    final isReturn = t.type == TxnType.returnGoods;
                    final spName = ledger.salesperson(t.salespersonId ?? '')?.name ??
                        '(former salesperson)';
                    final pieces =
                        t.lines.fold<int>(0, (s, l) => s + l.qty);
                    final amount = t.linesSell;
                    return AppCard(
                      onTap: () {
                        if (isReturn) {
                          showEntryDetail(context, ref, t);
                        } else {
                          showReceiptSheet(context, ref, t.id);
                        }
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(spName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    if (isReturn) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.danger
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text('Return',
                                            style: TextStyle(
                                                color: AppColors.danger,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                    '${prettyDate(t.date)} · '
                                    '${formatQty(pieces)} '
                                    '${pieces == 1 ? 'piece' : 'pieces'}',
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          Text(
                            isReturn
                                ? '−${money.format(amount)}'
                                : money.format(amount),
                            style: tabularFigures.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isReturn
                                  ? AppColors.danger
                                  : AppColors.ink,
                            ),
                          ),
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
