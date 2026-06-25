import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import 'stockin_sheet.dart' show isoDate;

/// Record an expense: lowers cash and profit for the period (Section 7.8).
Future<void> showExpenseSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(context, const _ExpenseSheet());
}

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet();

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  final _category = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();
  bool _recurring = false;

  @override
  void dispose() {
    _category.dispose();
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

    final category = _category.text.trim();
    if (category.isEmpty) {
      showError(context, 'Enter a category.');
      return;
    }
    final amount = money.parse(_amount.text);
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount greater than zero.');
      return;
    }

    try {
      await repo.addExpense(
        category: category,
        amount: amount,
        date: _date,
        recurring: _recurring,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, 'Expense recorded');
  }

  @override
  Widget build(BuildContext context) {
    final cats =
        ref.watch(listValuesProvider('expense_category')).valueOrNull ?? const [];
    final current = _category.text.trim().toLowerCase();
    final chips =
        cats.where((c) => c.toLowerCase() != current).take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Record expense'),
        TextField(
          key: const Key('expense_category'),
          controller: _category,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Category'),
          onChanged: (_) => setState(() {}),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in chips)
                ActionChip(
                  label: Text(c),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: AppColors.hairline),
                  onPressed: () {
                    _category.text = c;
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('expense_amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: 12),
        _DateRow(date: _date, onTap: _pickDate),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.positive,
          title: const Text('Mark as monthly recurring'),
          value: _recurring,
          onChanged: (v) => setState(() => _recurring = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
            key: const Key('expense_save'),
            onPressed: _save,
            child: const Text('Record expense')),
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
