import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import '../domain/models.dart';

/// Add or edit a salesperson (Section 7.9).
Future<void> showSalespersonForm(BuildContext context, WidgetRef ref,
    {Salesperson? existing}) {
  return showAppSheet<void>(context, _SalespersonForm(existing: existing));
}

class _SalespersonForm extends ConsumerStatefulWidget {
  final Salesperson? existing;
  const _SalespersonForm({this.existing});

  @override
  ConsumerState<_SalespersonForm> createState() => _SalespersonFormState();
}

class _SalespersonFormState extends ConsumerState<_SalespersonForm> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _opening;
  late final TextEditingController _margin;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final money = ref.read(moneyProvider);
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _opening = TextEditingController(
        text: (s == null || s.opening == 0) ? '' : money.editValue(s.opening));
    _margin = TextEditingController(
        text: (s == null || s.openingMarginBp == 0)
            ? ''
            : (s.openingMarginBp / 100).toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _opening.dispose();
    _margin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final money = ref.read(moneyProvider);
    final repo = ref.read(repositoryProvider);

    final name = _name.text.trim();
    if (name.isEmpty) {
      showError(context, 'Enter a name.');
      return;
    }

    var opening = 0;
    if (_opening.text.trim().isNotEmpty) {
      final v = money.parse(_opening.text);
      if (v == null) {
        showError(context, 'Enter a valid opening balance.');
        return;
      }
      opening = v;
    }

    var marginBp = 0;
    if (_margin.text.trim().isNotEmpty) {
      final pct = double.tryParse(_margin.text.trim());
      if (pct == null) {
        showError(context, 'Enter a valid opening margin percentage.');
        return;
      }
      marginBp = (pct * 100).round();
    }

    final Salesperson sp;
    if (widget.existing != null) {
      sp = widget.existing!.copyWith(
        name: name,
        phone: _phone.text.trim(),
        opening: opening,
        openingMarginBp: marginBp,
      );
    } else {
      sp = Salesperson(
        id: newId(),
        name: name,
        phone: _phone.text.trim(),
        opening: opening,
        openingMarginBp: marginBp,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    try {
      await repo.upsertSalesperson(sp);
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, _isEdit ? 'Salesperson updated' : 'Salesperson added');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(_isEdit ? 'Edit salesperson' : 'Add salesperson'),
        TextField(
          key: const Key('sp_name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('sp_opening'),
          controller: _opening,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(labelText: 'Opening balance (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _margin,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Opening margin % (optional)',
            helperText: 'Margin on the opening balance, e.g. 20',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('sp_save'),
          onPressed: _save,
          child: Text(_isEdit ? 'Save changes' : 'Add salesperson'),
        ),
      ],
    );
  }
}
