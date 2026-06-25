import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../services/receipt.dart';

/// Read-only entry detail with a delete-and-re-add correction model
/// (Section 8). Deleting recalculates every derived figure instantly.
Future<void> showEntryDetail(BuildContext context, WidgetRef ref, Txn txn) {
  return showAppSheet<void>(context, _EntryDetail(txn: txn));
}

class _EntryDetail extends ConsumerWidget {
  final Txn txn;
  const _EntryDetail({required this.txn});

  String _title() => switch (txn.type) {
        TxnType.stockin => 'Stock added',
        TxnType.sale => 'Took goods',
        TxnType.returnGoods => 'Returned goods',
        TxnType.payment => 'Payment received',
        TxnType.expense => 'Expense',
      };

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final ok = await confirm(context,
        title: 'Delete this entry',
        message:
            'This permanently removes the entry and recalculates all figures. Continue?',
        confirmLabel: 'Delete',
        danger: true);
    if (!ok) return;
    try {
      await repo.deleteTransaction(txn.id);
    } catch (e) {
      if (context.mounted) {
        showError(context, 'Something went wrong. Please try again.');
      }
      return;
    }
    if (context.mounted) {
      Navigator.pop(context);
      showToast(context, 'Entry deleted');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final ledger = ref.watch(ledgerProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(_title()),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _body(context, money, ledger),
          ),
        ),
        const SizedBox(height: 16),
        if (txn.type == TxnType.sale) ...[
          OutlinedButton.icon(
            onPressed: () => showReceiptSheet(context, ref, txn.id),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View receipt'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: const BorderSide(color: AppColors.hairline),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: () => _delete(context, ref),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Delete this entry'),
        ),
      ],
    );
  }

  List<Widget> _body(BuildContext context, Money money, Ledger? ledger) {
    final rows = <Widget>[
      _kv('Date', prettyDate(txn.date)),
    ];

    switch (txn.type) {
      case TxnType.stockin:
        final p = ledger?.product(txn.productId ?? '');
        rows.add(_kv('Product',
            p == null ? '(deleted product)' : _productLabel(p)));
        rows.add(_kv('Quantity', formatQty(txn.qty ?? 0)));
        rows.add(_kv('Buy price', money.format(txn.unitBuy ?? 0)));
        rows.add(_divider());
        rows.add(_kv('Cost',
            money.format((txn.qty ?? 0) * (txn.unitBuy ?? 0)),
            emphasis: true));
        break;

      case TxnType.sale:
      case TxnType.returnGoods:
        final sp = ledger?.salesperson(txn.salespersonId ?? '');
        rows.add(_kv('Salesperson',
            sp?.name ?? '(former salesperson)'));
        rows.add(_divider());
        for (final l in txn.lines) {
          final p = ledger?.product(l.productId);
          final name = p == null ? '(deleted product)' : _productLabel(p);
          rows.add(_kv('$name  ×${formatQty(l.qty)}',
              money.format(l.lineSell)));
        }
        rows.add(_divider());
        rows.add(_kv(
            txn.type == TxnType.sale ? 'Sale total' : 'Credit',
            money.format(txn.linesSell),
            emphasis: true));
        break;

      case TxnType.payment:
        final sp = ledger?.salesperson(txn.salespersonId ?? '');
        rows.add(_kv('Salesperson', sp?.name ?? '(former salesperson)'));
        rows.add(_divider());
        rows.add(_kv('Amount', money.format(txn.amount ?? 0),
            emphasis: true));
        break;

      case TxnType.expense:
        rows.add(_kv('Category', txn.category ?? ''));
        if (txn.recurring) rows.add(_kv('Recurring', 'Monthly'));
        rows.add(_divider());
        rows.add(_kv('Amount', money.format(txn.amount ?? 0),
            emphasis: true));
        break;
    }

    if ((txn.note ?? '').trim().isNotEmpty) {
      rows.add(_divider());
      rows.add(_kv('Note', txn.note!.trim()));
    }
    return rows;
  }

  String _productLabel(Product p) =>
      p.size.isEmpty ? p.name : '${p.name} · ${p.size}';

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Divider(height: 1),
      );

  Widget _kv(String k, String v, {bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    color: emphasis ? AppColors.ink : AppColors.muted,
                    fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400)),
          ),
          const SizedBox(width: 12),
          Text(v,
              textAlign: TextAlign.right,
              style: tabularFigures.copyWith(
                  fontWeight: emphasis ? FontWeight.w600 : FontWeight.w500)),
        ],
      ),
    );
  }
}
