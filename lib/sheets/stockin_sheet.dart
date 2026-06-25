import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import 'product_picker.dart';

/// Record a stock-in: raises stock, lowers cash (Section 7.2).
///
/// Pass [existing] to edit an entry instead — saving re-creates it atomically
/// (Section 8) so all derived figures stay consistent.
Future<void> showStockInSheet(BuildContext context, WidgetRef ref,
    {String? productId, Txn? existing}) {
  return showAppSheet<void>(
      context, _StockInSheet(productId: productId, existing: existing));
}

class _StockInSheet extends ConsumerStatefulWidget {
  final String? productId;
  final Txn? existing;
  const _StockInSheet({this.productId, this.existing});

  @override
  ConsumerState<_StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends ConsumerState<_StockInSheet> {
  String? _productId;
  final _qty = TextEditingController();
  final _unitBuy = TextEditingController();
  String _date = todayIso();
  bool _unitBuyTouched = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _productId = existing.productId;
      _qty.text = '${existing.qty ?? 0}';
      _unitBuy.text = ref.read(moneyProvider).editValue(existing.unitBuy ?? 0);
      _date = existing.date;
      _unitBuyTouched = true; // keep the saved price; don't re-sync from product
    } else {
      _productId = widget.productId;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _unitBuy.dispose();
    super.dispose();
  }

  void _syncUnitBuy(Product? p) {
    if (p == null) return;
    if (!_unitBuyTouched) {
      _unitBuy.text = ref.read(moneyProvider).editValue(p.buyPrice);
    }
  }

  Future<void> _pickProduct(Ledger ledger) async {
    final p = await showProductPicker(
      context,
      ledger: ledger,
      money: ref.read(moneyProvider),
    );
    if (p != null) {
      setState(() {
        _productId = p.id;
        _unitBuyTouched = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = isoDate(picked));
    }
  }

  Future<void> _save() async {
    final money = ref.read(moneyProvider);
    final repo = ref.read(repositoryProvider);

    if (_productId == null) {
      showError(context, 'Pick a product.');
      return;
    }
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null || qty <= 0) {
      showError(context, 'Enter a quantity greater than zero.');
      return;
    }
    final unitBuy = money.parse(_unitBuy.text);
    if (unitBuy == null) {
      showError(context, 'Enter a valid buy price.');
      return;
    }

    try {
      if (_isEdit) {
        await repo.editStockIn(
          id: widget.existing!.id,
          productId: _productId!,
          qty: qty,
          unitBuy: unitBuy,
          date: _date,
          note: widget.existing!.note,
        );
      } else {
        await repo.addStockIn(
          productId: _productId!,
          qty: qty,
          unitBuy: unitBuy,
          date: _date,
        );
      }
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, _isEdit ? 'Stock updated' : 'Stock added');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider).valueOrNull;
    final selected =
        _productId == null ? null : ledger?.product(_productId!);

    // Keep unit-buy in sync with the chosen product (until user edits it).
    if (selected != null) _syncUnitBuy(selected);

    final locked = widget.productId != null || _isEdit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(_isEdit ? 'Edit stock' : 'Add stock'),
        if (!locked)
          ProductField(
            key: const Key('stockin_product'),
            product: selected,
            onTap: () {
              if (ledger != null) _pickProduct(ledger);
            },
          )
        else if (selected != null)
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(_productLabel(selected),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('In stock ${formatQty(ledger!.stock(selected.id))}',
                    style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('stockin_qty'),
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('stockin_buy'),
                controller: _unitBuy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _unitBuyTouched = true,
                decoration: const InputDecoration(labelText: 'Buy price'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DateField(date: _date, onTap: _pickDate),
        const SizedBox(height: 16),
        if (selected != null && !_isEdit)
          Text('This raises stock and lowers cash.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        FilledButton(
            key: const Key('stockin_save'),
            onPressed: _save,
            child: Text(_isEdit ? 'Save changes' : 'Add stock')),
      ],
    );
  }

  String _productLabel(Product p) {
    final size = p.size.isEmpty ? '' : ' · ${p.size}';
    return '${p.name}$size';
  }
}

/// Date picker field shared across sheets.
class _DateField extends StatelessWidget {
  final String date;
  final VoidCallback onTap;
  const _DateField({required this.date, required this.onTap});

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

/// Local 'YYYY-MM-DD' from a DateTime (mirrors Period.fmtDate).
String isoDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
