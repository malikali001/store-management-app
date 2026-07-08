import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/models.dart';
import 'stockin_sheet.dart' show isoDate;

/// Record that a shop bought from us: a simple amount + date (no credit, no
/// stock effect), with an optional link to the salesperson who made the sale.
Future<void> showShopPurchaseSheet(BuildContext context, WidgetRef ref,
    {required String shopId}) {
  return showAppSheet<void>(context, _ShopPurchaseSheet(shopId: shopId));
}

class _ShopPurchaseSheet extends ConsumerStatefulWidget {
  final String shopId;
  const _ShopPurchaseSheet({required this.shopId});

  @override
  ConsumerState<_ShopPurchaseSheet> createState() => _ShopPurchaseSheetState();
}

class _ShopPurchaseSheetState extends ConsumerState<_ShopPurchaseSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _spId; // optional salesperson
  String _date = todayIso();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
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

    final amount = money.parse(_amount.text);
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount greater than zero.');
      return;
    }

    try {
      await repo.addShopPurchase(
        shopId: widget.shopId,
        amount: amount,
        date: _date,
        salespersonId: _spId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, 'Purchase recorded');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider).valueOrNull;
    final people = (ledger?.salespersons ?? const <Salesperson>[])
        .where((s) => !s.archived)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Record purchase'),
        TextField(
          key: const Key('purchase_amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount bought',
            helperText: 'Total value the shop bought',
          ),
        ),
        const SizedBox(height: 12),
        _DateRow(date: _date, onTap: _pickDate),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: const Key('purchase_salesperson'),
          initialValue: _spId,
          isExpanded: true,
          decoration:
              const InputDecoration(labelText: 'Salesperson (optional)'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final s in people)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _spId = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('purchase_save'),
          onPressed: _save,
          child: const Text('Record purchase'),
        ),
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
