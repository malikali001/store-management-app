import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/period.dart';

const _kRecurringMonthKey = 'recurring_prompt_month';

String _currentMonthKey(DateTime now) =>
    '${now.year}-${now.month.toString().padLeft(2, '0')}';

/// On the first launch of a new month, offer to add this month's copies of the
/// expenses the user tagged as monthly recurring (Section 9.5). Never posts
/// anything silently — the user taps once to add. Shows at most once per month.
Future<void> maybeShowRecurringPrompt(
    BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final now = DateTime.now();
  final monthKey = _currentMonthKey(now);

  final lastShown = await repo.rawSetting(_kRecurringMonthKey);
  if (lastShown == monthKey) return; // already handled this month

  final ledger = await repo.loadLedger();
  final templates =
      ledger.recurringExpenseTemplates(Period.thisMonth(now));

  // Mark as shown regardless, so we don't nag again this month.
  await repo.setSetting(_kRecurringMonthKey, monthKey);

  if (templates.isEmpty) return;
  if (!context.mounted) return;
  await showAppSheet(
      context, _RecurringSheet(templates: templates));
}

class _RecurringSheet extends ConsumerStatefulWidget {
  final List<({String category, int amount})> templates;
  const _RecurringSheet({required this.templates});

  @override
  ConsumerState<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends ConsumerState<_RecurringSheet> {
  late final Set<String> _selected =
      widget.templates.map((t) => t.category).toSet();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Monthly expenses'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'A new month has started. Add this month\'s recurring expenses?',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final t in widget.templates)
                CheckboxListTile(
                  value: _selected.contains(t.category),
                  onChanged: _saving
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              _selected.add(t.category);
                            } else {
                              _selected.remove(t.category);
                            }
                          }),
                  activeColor: AppColors.positive,
                  title: Text(t.category),
                  secondary: Text(money.format(t.amount), style: tabularFigures),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving || _selected.isEmpty ? null : _add,
          child: Text(_selected.isEmpty
              ? 'Select at least one'
              : 'Add ${_selected.length} to this month'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
      ],
    );
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final date = todayIso();
    var count = 0;
    for (final t in widget.templates) {
      if (!_selected.contains(t.category)) continue;
      await repo.addExpense(
          category: t.category, amount: t.amount, date: date, recurring: true);
      count++;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, 'Added $count recurring ${count == 1 ? 'expense' : 'expenses'}');
  }
}
