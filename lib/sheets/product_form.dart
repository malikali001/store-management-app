import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import '../domain/models.dart';

/// Add or edit a product (Section 7.3).
Future<void> showProductForm(BuildContext context, WidgetRef ref,
    {Product? existing}) {
  return showAppSheet<void>(context, _ProductForm(existing: existing));
}

class _ProductForm extends ConsumerStatefulWidget {
  final Product? existing;
  const _ProductForm({this.existing});

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final TextEditingController _code;
  late final TextEditingController _size;
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _category;
  late final TextEditingController _buy;
  late final TextEditingController _sell;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final money = ref.read(moneyProvider);
    final p = widget.existing;
    _code = TextEditingController(text: p?.code ?? '');
    _size = TextEditingController(text: p?.size ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _buy = TextEditingController(text: p == null ? '' : money.editValue(p.buyPrice));
    _sell = TextEditingController(text: p == null ? '' : money.editValue(p.sellPrice));
  }

  @override
  void dispose() {
    _code.dispose();
    _size.dispose();
    _name.dispose();
    _brand.dispose();
    _category.dispose();
    _buy.dispose();
    _sell.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final money = ref.read(moneyProvider);
    final repo = ref.read(repositoryProvider);

    final name = _name.text.trim();
    if (name.isEmpty) {
      showError(context, 'Enter a product name.');
      return;
    }
    final buy = money.parse(_buy.text);
    if (buy == null || buy < 0) {
      showError(context, 'Enter a valid buy price.');
      return;
    }
    final sell = money.parse(_sell.text);
    if (sell == null || sell <= 0) {
      showError(context, 'Enter a sell price greater than zero.');
      return;
    }

    final code = _code.text.trim();
    if (code.isNotEmpty &&
        await repo.codeExists(code, exceptId: widget.existing?.id)) {
      if (!mounted) return;
      final go = await confirm(context,
          title: 'Duplicate code',
          message: 'A product with this code already exists. Save anyway?',
          confirmLabel: 'Save anyway');
      if (!go) return;
    }

    final Product product;
    if (widget.existing != null) {
      product = widget.existing!.copyWith(
        code: code,
        name: name,
        brand: _brand.text.trim(),
        category: _category.text.trim(),
        size: _size.text.trim(),
        buyPrice: buy,
        sellPrice: sell,
      );
    } else {
      product = Product(
        id: newId(),
        code: code,
        name: name,
        brand: _brand.text.trim(),
        category: _category.text.trim(),
        size: _size.text.trim(),
        buyPrice: buy,
        sellPrice: sell,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    try {
      await repo.upsertProduct(product);
    } catch (e) {
      if (mounted) showError(context, _errText(e));
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, _isEdit ? 'Product updated' : 'Product added');
  }

  Future<void> _delete() async {
    final repo = ref.read(repositoryProvider);
    final id = widget.existing!.id;
    try {
      final ok = await confirm(context,
          title: 'Delete product',
          message: 'Delete this product permanently?',
          confirmLabel: 'Delete',
          danger: true);
      if (!ok) return;
      await repo.deleteProduct(id);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Product deleted');
    } on DomainError catch (e) {
      if (!mounted) return;
      final archive = await confirm(context,
          title: 'Cannot delete',
          message: '${e.message}\n\nArchive it instead?',
          confirmLabel: 'Archive');
      if (!archive) return;
      await repo.archiveProduct(id);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Product archived');
    } catch (e) {
      if (mounted) showError(context, _errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final brands = ref.watch(listValuesProvider('brand')).valueOrNull ?? const [];
    final categories =
        ref.watch(listValuesProvider('category')).valueOrNull ?? const [];
    final sizes = ref.watch(listValuesProvider('size')).valueOrNull ?? const [];

    // Existing product names, so adding another brand/size of the same product
    // is a pick rather than a re-type. Picking a known name fills its category.
    final products =
        ref.watch(ledgerProvider).valueOrNull?.products ?? const <Product>[];
    final nameSuggestions = <String>{
      for (final p in products)
        if (!p.archived && p.name.trim().isNotEmpty) p.name.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final categoryByName = <String, String>{};
    for (final p in products) {
      if (p.archived || p.category.trim().isEmpty) continue;
      categoryByName.putIfAbsent(p.name.trim().toLowerCase(), () => p.category.trim());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(_isEdit ? 'Edit product' : 'Add product'),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Code (optional)'),
        ),
        const SizedBox(height: 12),
        _SuggestField(
          controller: _size,
          label: 'Size (optional)',
          suggestions: sizes,
        ),
        const SizedBox(height: 12),
        _SuggestField(
          fieldKey: const Key('product_name'),
          controller: _name,
          label: 'Name',
          suggestions: nameSuggestions,
          onSelected: (v) {
            final cat = categoryByName[v.trim().toLowerCase()];
            if (cat != null && _category.text.trim().isEmpty) {
              _category.text = cat;
            }
          },
        ),
        const SizedBox(height: 12),
        _SuggestField(
          controller: _brand,
          label: 'Brand',
          suggestions: brands,
        ),
        const SizedBox(height: 12),
        _SuggestField(
          controller: _category,
          label: 'Category',
          suggestions: categories,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('product_buy'),
                controller: _buy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Buy price'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('product_sell'),
                controller: _sell,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Sell price'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('product_save'),
          onPressed: _save,
          child: Text(_isEdit ? 'Save changes' : 'Add product'),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _delete,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger),
            ),
            child: const Text('Delete'),
          ),
        ],
      ],
    );
  }
}

String _errText(Object e) =>
    e is DomainError ? e.message : 'Something went wrong. Please try again.';

/// A text field that shows quick-pick suggestion chips below it.
class _SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final Key? fieldKey;
  final ValueChanged<String>? onSelected;
  const _SuggestField({
    required this.controller,
    required this.label,
    required this.suggestions,
    this.fieldKey,
    this.onSelected,
  });

  @override
  State<_SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<_SuggestField> {
  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim().toLowerCase();
    final chips = widget.suggestions
        .where((s) => s.toLowerCase() != current)
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label),
          onChanged: (_) => setState(() {}),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in chips)
                ActionChip(
                  label: Text(s),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: AppColors.hairline),
                  onPressed: () {
                    widget.controller.text = s;
                    widget.onSelected?.call(s);
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
