import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/models.dart';
import 'stockin_sheet.dart' show isoDate;

/// Record a payment: lowers owed, raises cash, recognises profit (Section 7.7).
Future<void> showPaymentSheet(BuildContext context, WidgetRef ref,
    {String? salespersonId}) {
  return showAppSheet<void>(context, _PaymentSheet(salespersonId: salespersonId));
}

class _PaymentSheet extends ConsumerStatefulWidget {
  final String? salespersonId;
  const _PaymentSheet({this.salespersonId});

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  String? _spId;
  final _amount = TextEditingController();
  String _date = todayIso();

  @override
  void initState() {
    super.initState();
    _spId = widget.salespersonId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = isoDate(picked));
  }

  Future<void> _save() async {
    final money = ref.read(moneyProvider);
    final repo = ref.read(repositoryProvider);
    final ledger = ref.read(ledgerProvider).valueOrNull;

    if (_spId == null) {
      showError(context, 'Pick a salesperson.');
      return;
    }
    final amount = money.parse(_amount.text);
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount greater than zero.');
      return;
    }

    final oldBalance = ledger?.balance(_spId!) ?? 0;
    if (amount > oldBalance) {
      final go = await confirm(context,
          title: 'More than they owe',
          message:
              'This is more than they owe — it creates a credit. Continue?',
          confirmLabel: 'Continue');
      if (!go) return;
    }

    try {
      await repo.addPayment(salespersonId: _spId!, amount: amount, date: _date);
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    final newBalance = oldBalance - amount;
    Navigator.pop(context);
    showToast(context, 'New balance: ${money.format(newBalance)}');
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyProvider);
    final ledger = ref.watch(ledgerProvider).valueOrNull;
    final people = (ledger?.salespersons ?? const <Salesperson>[])
        .where((s) => !s.archived)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final balance = _spId == null ? null : ledger?.balance(_spId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Record payment'),
        DropdownButtonFormField<String>(
          key: const Key('payment_salesperson'),
          initialValue: _spId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Salesperson'),
          items: [
            for (final s in people)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _spId = v),
        ),
        if (balance != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current balance',
                    style: TextStyle(color: AppColors.muted)),
                Text(money.format(balance),
                    style: tabularFigures.copyWith(
                      fontWeight: FontWeight.w600,
                      color: balance > 0 ? AppColors.danger : AppColors.ink,
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('payment_amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: 12),
        _DateRow(date: _date, onTap: _pickDate),
        const SizedBox(height: 20),
        FilledButton(
            key: const Key('payment_save'),
            onPressed: _save,
            child: const Text('Record payment')),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final String date;
  final VoidCallback onTap;
  const _DateRow({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date'),
        child: Row(
          children: [
            Expanded(child: Text(prettyDate(date))),
            Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
