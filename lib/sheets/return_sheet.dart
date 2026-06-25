import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import 'product_picker.dart';
import 'stockin_sheet.dart' show isoDate;

/// Return goods: restores stock, lowers owed (Section 7.6). No receipt.
Future<void> showReturnSheet(BuildContext context, WidgetRef ref,
    {String? salespersonId}) {
  return showAppSheet<void>(context, _ReturnSheet(salespersonId: salespersonId));
}

class _DraftLine {
  String productId;
  int qty;
  int unitSell; // current product snapshot, minor units
  _DraftLine({required this.productId, required this.qty, required this.unitSell});
}

class _ReturnSheet extends ConsumerStatefulWidget {
  final String? salespersonId;
  const _ReturnSheet({this.salespersonId});

  @override
  ConsumerState<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<_ReturnSheet> {
  String? _spId;
  final List<_DraftLine> _lines = [];
  String _date = todayIso();

  @override
  void initState() {
    super.initState();
    _spId = widget.salespersonId;
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

  int get _total => _lines.fold(0, (s, l) => s + l.qty * l.unitSell);

  /// Net taken (sale qty − return qty) of [productId] by the salesperson.
  int _netTaken(Ledger ledger, String productId) {
    if (_spId == null) return 0;
    var n = 0;
    for (final t in ledger.txns) {
      if (t.salespersonId != _spId) continue;
      if (t.type == TxnType.sale) {
        for (final l in t.lines) {
          if (l.productId == productId) n += l.qty;
        }
      } else if (t.type == TxnType.returnGoods) {
        for (final l in t.lines) {
          if (l.productId == productId) n -= l.qty;
        }
      }
    }
    return n;
  }

  Future<void> _addLine(Ledger ledger) async {
    final money = ref.read(moneyProvider);
    final result = await showAppSheet<_DraftLine>(
      context,
      _LineEditor(ledger: ledger, money: money),
    );
    if (result != null) setState(() => _lines.add(result));
  }

  Future<void> _editLine(Ledger ledger, _DraftLine line) async {
    final money = ref.read(moneyProvider);
    final result = await showAppSheet<_DraftLine>(
      context,
      _LineEditor(ledger: ledger, money: money, existing: line),
    );
    if (result != null) {
      setState(() {
        line.productId = result.productId;
        line.qty = result.qty;
        line.unitSell = result.unitSell;
      });
    }
  }

  Future<void> _save(Ledger ledger) async {
    final repo = ref.read(repositoryProvider);
    if (_spId == null) {
      showError(context, 'Pick a salesperson.');
      return;
    }
    if (_lines.isEmpty) {
      showError(context, 'Add at least one item.');
      return;
    }

    // Warn (but allow) if any return qty exceeds net taken of that product.
    // Aggregate by product so duplicate lines are summed.
    final byProduct = <String, int>{};
    for (final l in _lines) {
      byProduct[l.productId] = (byProduct[l.productId] ?? 0) + l.qty;
    }
    for (final entry in byProduct.entries) {
      final net = _netTaken(ledger, entry.key);
      if (entry.value > net) {
        final p = ledger.product(entry.key);
        final name = p == null ? 'this product' : p.name;
        final go = await confirm(context,
            title: 'More than taken',
            message:
                'Returning more $name than this salesperson has taken (${formatQty(net)}). Continue?',
            confirmLabel: 'Continue');
        if (!go) return;
        break;
      }
    }

    final lines = <({String productId, int qty, int unitSell, int unitBuy})>[];
    for (final l in _lines) {
      final p = ledger.product(l.productId);
      lines.add((
        productId: l.productId,
        qty: l.qty,
        unitSell: l.unitSell,
        unitBuy: p?.buyPrice ?? 0,
      ));
    }

    try {
      await repo.addSaleOrReturn(
        type: TxnType.returnGoods,
        salespersonId: _spId!,
        date: _date,
        lines: lines,
      );
    } catch (e) {
      if (mounted) showError(context, 'Something went wrong. Please try again.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showToast(context, 'Return recorded');
  }

  @override
  Widget build(BuildContext context) {
    final money = ref.watch(moneyProvider);
    final ledger = ref.watch(ledgerProvider).valueOrNull;
    if (ledger == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final people = ledger.salespersons.where((s) => !s.archived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Return goods'),
        DropdownButtonFormField<String>(
          key: const Key('return_salesperson'),
          initialValue: _spId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Salesperson'),
          items: [
            for (final s in people)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _spId = v),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Items'),
        for (final l in _lines)
          _LineRow(
            ledger: ledger,
            money: money,
            line: l,
            onTap: () => _editLine(ledger, l),
            onRemove: () => setState(() => _lines.remove(l)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('return_add_item'),
          onPressed: () => _addLine(ledger),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            side: BorderSide(color: AppColors.hairline),
          ),
        ),
        const SizedBox(height: 16),
        _DateRow(date: _date, onTap: _pickDate),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Credit',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Text(money.format(_total),
                  style: tabularFigures.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.positive)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
            key: const Key('return_save'),
            onPressed: () => _save(ledger),
            child: const Text('Save return')),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  final Ledger ledger;
  final Money money;
  final _DraftLine line;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _LineRow({
    required this.ledger,
    required this.money,
    required this.line,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final p = ledger.product(line.productId);
    final name = p == null
        ? '(deleted product)'
        : (p.size.isEmpty ? p.name : '${p.name} · ${p.size}');
    final brand = p?.brand.trim() ?? '';
    final detail = [
      if (brand.isNotEmpty) brand,
      '${formatQty(line.qty)} × ${money.format(line.unitSell)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            Text(money.format(line.qty * line.unitSell),
                style: tabularFigures.copyWith(fontWeight: FontWeight.w600)),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: AppColors.muted),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEditor extends ConsumerStatefulWidget {
  final Ledger ledger;
  final Money money;
  final _DraftLine? existing;
  const _LineEditor({
    required this.ledger,
    required this.money,
    this.existing,
  });

  @override
  ConsumerState<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends ConsumerState<_LineEditor> {
  String? _productId;
  final _qty = TextEditingController();
  final _unitSell = TextEditingController();
  bool _unitTouched = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _productId = e.productId;
      _qty.text = '${e.qty}';
      _unitSell.text = widget.money.editValue(e.unitSell);
      _unitTouched = true;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _unitSell.dispose();
    super.dispose();
  }

  void _onProductChanged(String? id) {
    setState(() {
      _productId = id;
      if (!_unitTouched && id != null) {
        final p = widget.ledger.product(id);
        if (p != null) _unitSell.text = widget.money.editValue(p.sellPrice);
      }
    });
  }

  Future<void> _pickProduct() async {
    final p = await showProductPicker(
      context,
      ledger: widget.ledger,
      money: widget.money,
    );
    if (p != null) _onProductChanged(p.id);
  }

  void _submit() {
    if (_productId == null) {
      showError(context, 'Pick a product.');
      return;
    }
    final qty = int.tryParse(_qty.text.trim());
    if (qty == null || qty <= 0) {
      showError(context, 'Enter a quantity greater than zero.');
      return;
    }
    final unitSell = widget.money.parse(_unitSell.text);
    if (unitSell == null) {
      showError(context, 'Enter a valid unit price.');
      return;
    }
    Navigator.pop(context,
        _DraftLine(productId: _productId!, qty: qty, unitSell: unitSell));
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _productId == null ? null : widget.ledger.product(_productId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(widget.existing == null ? 'Add item' : 'Edit item'),
        ProductField(
          key: const Key('line_product'),
          product: selected,
          onTap: _pickProduct,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('line_qty'),
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('line_unit'),
                controller: _unitSell,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _unitTouched = true,
                decoration: const InputDecoration(labelText: 'Unit price'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
            key: const Key('line_add'),
            onPressed: _submit,
            child: Text(widget.existing == null ? 'Add' : 'Save')),
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
