import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../sheets/entry_detail_sheet.dart';
import '../sheets/product_form.dart';
import '../sheets/stockin_sheet.dart';
import '../services/receipt.dart';

/// Section 7.2 — a single product's detail view: stock & pricing, the value it
/// holds and has generated, and its full movement history.
class ProductDetailScreen extends ConsumerWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ledgerAsync.maybeWhen(
          data: (l) => l.product(productId)?.name ?? '(deleted product)',
          orElse: () => '',
        )),
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildBody(context, ref, ledger),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Ledger ledger) {
    final money = ref.watch(moneyProvider);
    final product = ledger.product(productId);
    if (product == null) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'This product has been deleted.',
      );
    }

    final stock = ledger.stock(productId);
    final isLow = stock <= ledger.settings.lowStock;
    final margin = product.sellPrice - product.buyPrice;
    final marginPct =
        product.buyPrice > 0 ? (margin * 100 / product.buyPrice).round() : null;

    final subtitle = [
      if (product.brand.trim().isNotEmpty) product.brand.trim(),
      if (product.size.trim().isNotEmpty) product.size.trim(),
      if (product.code.trim().isNotEmpty) product.code.trim(),
      if (product.category.trim().isNotEmpty) product.category.trim(),
    ].join(' · ');

    final movements = ledger.productMovements(productId).reversed.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(subtitle,
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
            ),
          if (product.archived)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Banner(
                icon: Icons.archive_outlined,
                text: 'This product is archived — hidden from lists.',
              ),
            ),
          ResponsiveCardGrid(
            cards: [
              MetricCard(
                label: isLow ? 'Current stock · low' : 'Current stock',
                value: formatQty(stock),
                valueColor: isLow ? AppColors.warning : null,
              ),
              MetricCard(
                  label: 'Sell price', value: money.format(product.sellPrice)),
              MetricCard(
                  label: 'Buy price', value: money.format(product.buyPrice)),
              MetricCard(
                label: marginPct == null ? 'Margin / unit' : 'Margin · $marginPct%',
                value: money.format(margin),
                valueColor: margin >= 0 ? AppColors.positive : AppColors.danger,
              ),
              MetricCard(
                  label: 'Stock value',
                  value: money.format(ledger.productStockValue(productId))),
              MetricCard(
                  label: 'Units sold', value: formatQty(ledger.unitsSold(productId))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add stock'),
                  onPressed: () =>
                      showStockInSheet(context, ref, productId: productId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                  onPressed: () =>
                      showProductForm(context, ref, existing: product),
                ),
              ),
            ],
          ),
          const SectionTitle('Movement history'),
          if (movements.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No movements yet',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < movements.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _MovementRow(
                      txn: movements[i],
                      productId: productId,
                      money: money,
                      onTap: () {
                        if (movements[i].type == TxnType.sale) {
                          showReceiptSheet(context, ref, movements[i].id);
                        } else {
                          showEntryDetail(context, ref, movements[i]);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One movement (stock-in / sale / return) as it affects this product's stock.
class _MovementRow extends StatelessWidget {
  final Txn txn;
  final String productId;
  final Money money;
  final VoidCallback onTap;
  const _MovementRow({
    required this.txn,
    required this.productId,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final int delta; // + adds stock, − removes
    String? detail;
    switch (txn.type) {
      case TxnType.stockin:
        label = 'Stock added';
        delta = txn.qty ?? 0;
        detail = 'at ${money.format(txn.unitBuy ?? 0)}';
        break;
      case TxnType.sale:
        label = 'Sold';
        delta = -_qtyOf(txn, productId);
        break;
      case TxnType.returnGoods:
        label = 'Returned';
        delta = _qtyOf(txn, productId);
        break;
      default:
        label = '';
        delta = 0;
    }
    final adds = delta >= 0;
    final subtitle = [prettyDate(txn.date), ?detail].join(' · ');

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
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text('${adds ? '+' : '−'}${formatQty(delta.abs())}',
                style: tabularFigures.copyWith(
                  fontWeight: FontWeight.w600,
                  color: adds ? AppColors.positive : AppColors.danger,
                )),
          ],
        ),
      ),
    );
  }

  static int _qtyOf(Txn t, String productId) => t.lines
      .where((l) => l.productId == productId)
      .fold(0, (s, l) => s + l.qty);
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Banner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warnSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: AppColors.warning, fontSize: 13))),
        ],
      ),
    );
  }
}
