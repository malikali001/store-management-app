import 'package:flutter/material.dart';

import '../app/format.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';

/// A searchable product picker (Section 7.5). Replaces the flat dropdown so a
/// large catalog is fast to search, and shows the **brand** so same-named
/// products from different brands are told apart.
///
/// Returns the chosen [Product], or null if dismissed. When [availableFor] is
/// given (sales), each row shows quantity available (net of the current draft);
/// otherwise it shows current stock.
Future<Product?> showProductPicker(
  BuildContext context, {
  required Ledger ledger,
  required Money money,
  int Function(String productId)? availableFor,
}) {
  return showAppSheet<Product>(
    context,
    _ProductPicker(ledger: ledger, money: money, availableFor: availableFor),
  );
}

/// A tappable form field that shows the currently selected product (name ·
/// size, with brand beneath) and opens [showProductPicker] when tapped.
class ProductField extends StatelessWidget {
  final Product? product;
  final VoidCallback onTap;
  const ProductField({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final title =
        p == null ? null : (p.size.isEmpty ? p.name : '${p.name} · ${p.size}');
    final brand = p?.brand.trim() ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Product'),
        child: Row(
          children: [
            Expanded(
              child: title == null
                  ? const Text('Select product',
                      style: TextStyle(color: AppColors.muted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (brand.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(brand,
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 13)),
                        ],
                      ],
                    ),
            ),
            const Icon(Icons.search, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final Ledger ledger;
  final Money money;
  final int Function(String productId)? availableFor;
  const _ProductPicker({
    required this.ledger,
    required this.money,
    this.availableFor,
  });

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Product p, String q) {
    if (q.isEmpty) return true;
    final hay =
        '${p.name} ${p.brand} ${p.code} ${p.category} ${p.size}'.toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final products = widget.ledger.products
        .where((p) => !p.archived && _matches(p, q))
        .toList()
      ..sort((a, b) {
        final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (n != 0) return n;
        final br = a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
        if (br != 0) return br;
        return a.size.toLowerCase().compareTo(b.size.toLowerCase());
      });

    final maxListHeight = MediaQuery.of(context).size.height * 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Select product'),
        TextField(
          key: const Key('product_picker_search'),
          controller: _search,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search name, brand, code, category',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: EmptyState(
                icon: Icons.search_off, message: 'No matching products'),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ProductRow(
                product: products[i],
                ledger: widget.ledger,
                money: widget.money,
                availableFor: widget.availableFor,
                onTap: () => Navigator.pop(context, products[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// One tappable product row: name · size, brand + code, sell price and the
/// quantity available (or current stock), with a low-stock badge.
class _ProductRow extends StatelessWidget {
  final Product product;
  final Ledger ledger;
  final Money money;
  final int Function(String productId)? availableFor;
  final VoidCallback onTap;
  const _ProductRow({
    required this.product,
    required this.ledger,
    required this.money,
    required this.availableFor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final title = p.size.isEmpty ? p.name : '${p.name} · ${p.size}';

    final subParts = [
      if (p.brand.trim().isNotEmpty) p.brand.trim(),
      if (p.code.trim().isNotEmpty) p.code.trim(),
    ];
    final subtitle = subParts.join(' · ');

    final stock = ledger.stock(p.id);
    final low = stock <= ledger.settings.lowStock;
    final qty = availableFor == null ? stock : availableFor!(p.id);
    final qtyLabel = availableFor == null ? 'Stock' : 'Available';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(money.format(p.sellPrice),
                  style: tabularFigures.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (low)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('low',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  Text('$qtyLabel ${formatQty(qty < 0 ? 0 : qty)}',
                      style: tabularFigures.copyWith(
                          color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
