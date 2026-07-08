import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../sheets/product_form.dart';
import 'product_detail_screen.dart';

/// How the products list is ordered.
enum ProductSort {
  nameAsc,
  stockAsc,
  stockDesc,
  priceDesc,
  priceAsc;

  String get label => switch (this) {
        ProductSort.nameAsc => 'Name (A–Z)',
        ProductSort.stockAsc => 'Stock: low to high',
        ProductSort.stockDesc => 'Stock: high to low',
        ProductSort.priceDesc => 'Price: high to low',
        ProductSort.priceAsc => 'Price: low to high',
      };
}

/// Section 7.2 — products list, grouped by brand + name.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _query = '';
  String? _category; // null = all categories
  ProductSort _sort = ProductSort.nameAsc;

  bool _matches(Product p, String q) {
    if (q.isEmpty) return true;
    final hay =
        '${p.name} ${p.brand} ${p.code} ${p.category}'.toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          PopupMenuButton<ProductSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (context) => [
              for (final s in ProductSort.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Icon(Icons.check,
                          size: 18,
                          color: s == _sort
                              ? AppColors.positive
                              : Colors.transparent),
                      const SizedBox(width: 8),
                      Text(s.label),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Add product',
            icon: const Icon(Icons.add),
            onPressed: () => showProductForm(context, ref),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildList(context, ledger),
      ),
    );
  }

  Widget _buildList(BuildContext context, Ledger ledger) {
    final money = ref.watch(moneyProvider);
    final q = _query.trim().toLowerCase();

    // Distinct categories present in the catalog, alphabetical.
    final categories = ledger.products
        .where((p) => !p.archived && p.category.trim().isNotEmpty)
        .map((p) => p.category.trim())
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Ignore a stale selection (e.g. its products were deleted/archived).
    final activeCategory =
        (_category != null && categories.contains(_category)) ? _category : null;

    final visible = ledger.products
        .where((p) =>
            !p.archived &&
            _matches(p, q) &&
            (activeCategory == null || p.category.trim() == activeCategory))
        .toList();

    // Group by product identity (name + category); brand and size are
    // variant dimensions shown per row.
    final groups = <String, List<Product>>{};
    for (final p in visible) {
      final key =
          '${p.name.trim().toLowerCase()}|||${p.category.trim().toLowerCase()}';
      (groups[key] ??= []).add(p);
    }
    // Order variants within each group, then order the groups, by the chosen
    // sort. Stock/price sorts fall back to name so ties stay stable.
    int stockOf(Product p) => ledger.stock(p.id);
    int byName(Product a, Product b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());

    Comparator<Product> variantCmp = switch (_sort) {
      ProductSort.nameAsc => _compareVariants,
      ProductSort.stockAsc => (a, b) => stockOf(a).compareTo(stockOf(b)),
      ProductSort.stockDesc => (a, b) => stockOf(b).compareTo(stockOf(a)),
      ProductSort.priceAsc => (a, b) => a.sellPrice.compareTo(b.sellPrice),
      ProductSort.priceDesc => (a, b) => b.sellPrice.compareTo(a.sellPrice),
    };

    final entries = groups.entries.map((e) {
      final items = [...e.value]..sort((a, b) {
          final c = variantCmp(a, b);
          return c != 0 ? c : _compareVariants(a, b);
        });
      return items;
    }).toList();

    entries.sort((a, b) {
      final int v;
      switch (_sort) {
        case ProductSort.nameAsc:
          v = 0; // fall through to name tiebreak below
          break;
        case ProductSort.stockAsc:
          v = a.map(stockOf).reduce((x, y) => x < y ? x : y).compareTo(
              b.map(stockOf).reduce((x, y) => x < y ? x : y));
          break;
        case ProductSort.stockDesc:
          v = b.map(stockOf).reduce((x, y) => x > y ? x : y).compareTo(
              a.map(stockOf).reduce((x, y) => x > y ? x : y));
          break;
        case ProductSort.priceAsc:
          v = a.map((p) => p.sellPrice).reduce((x, y) => x < y ? x : y).compareTo(
              b.map((p) => p.sellPrice).reduce((x, y) => x < y ? x : y));
          break;
        case ProductSort.priceDesc:
          v = b.map((p) => p.sellPrice).reduce((x, y) => x > y ? x : y).compareTo(
              a.map((p) => p.sellPrice).reduce((x, y) => x > y ? x : y));
          break;
      }
      return v != 0 ? v : byName(a.first, b.first);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search name, brand, code, category',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (categories.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: activeCategory == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in categories) ...[
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: c,
                    selected: activeCategory == c,
                    onTap: () => setState(() => _category = c),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: activeCategory != null || q.isNotEmpty
                      ? 'No products match your filter.'
                      : 'No products yet. Tap + to add one.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final items = entries[i];
                    final first = items.first;
                    final title = first.name;
                    final category = first.category.trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Flexible(
                                  child: Text(title,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (category.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(category,
                                      style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                          AppCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var j = 0; j < items.length; j++) ...[
                                  if (j > 0) const Divider(height: 1),
                                  _ProductRow(
                                    product: items[j],
                                    stock: ledger.stock(items[j].id),
                                    lowStock: ledger.settings.lowStock,
                                    money: money,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ProductDetailScreen(
                                            productId: items[j].id),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Sort variants within a product group by brand, then size.
int _compareVariants(Product a, Product b) {
  final br = a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
  if (br != 0) return br;
  return a.size.toLowerCase().compareTo(b.size.toLowerCase());
}

/// Per-row label for a variant: "brand · size", or whichever is present,
/// falling back to "Item" when the product has neither.
String variantLabel(Product p) {
  final parts = [
    if (p.brand.trim().isNotEmpty) p.brand.trim(),
    if (p.size.trim().isNotEmpty) p.size.trim(),
  ];
  return parts.isEmpty ? 'Item' : parts.join(' · ');
}

class _ProductRow extends StatelessWidget {
  final Product product;
  final int stock;
  final int lowStock;
  final Money money;
  final VoidCallback onTap;
  const _ProductRow({
    required this.product,
    required this.stock,
    required this.lowStock,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = stock <= lowStock;
    final sizeLabel = variantLabel(product);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(sizeLabel,
                          style:
                              const TextStyle(fontWeight: FontWeight.w500)),
                      if (isLow) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('low',
                              style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  if (product.code.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(product.code,
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money.format(product.sellPrice),
                    style:
                        tabularFigures.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('${formatQty(stock)} in stock',
                    style: tabularFigures.copyWith(
                        color: isLow ? AppColors.warning : AppColors.muted,
                        fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable category pill for the Products filter row.
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.positive,
        side: BorderSide(
            color: selected ? AppColors.positive : AppColors.hairline),
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
