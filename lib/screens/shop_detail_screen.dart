import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import '../sheets/shop_form.dart';
import '../sheets/shop_purchase_sheet.dart';

/// A single shop's profile: contact details, buying summary, loyalty badge and
/// its purchase history. Shops are external customers (retailers), separate
/// from salespersons.
class ShopDetailScreen extends ConsumerWidget {
  final String shopId;
  const ShopDetailScreen({super.key, required this.shopId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ledgerAsync.maybeWhen(
          data: (l) => l.shop(shopId)?.name ?? '(removed shop)',
          orElse: () => '',
        )),
        actions: [
          if (ledgerAsync.valueOrNull?.shop(shopId) != null)
            IconButton(
              tooltip: 'Edit shop',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showShopForm(context, ref,
                  existing: ledgerAsync.value!.shop(shopId)),
            ),
        ],
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
    final shop = ledger.shop(shopId);
    if (shop == null) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        message: 'This shop has been removed.',
      );
    }

    final now = DateTime.now();
    final segment = ledger.shopSegment(shopId, now);
    final total = ledger.totalBought(shopId);
    final thisMonth = ledger.boughtInPeriod(shopId, Period.thisMonth(now));
    final count = ledger.purchaseCount(shopId);
    final last = ledger.lastPurchaseDate(shopId);
    final isTopBuyer = total > 0 && total == ledger.topBoughtValue;

    final purchases = ledger.purchasesOf(shopId).reversed.toList(); // newest first

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShopSegmentBadge(segment),
              if (isTopBuyer) const TopBuyerBadge(),
            ],
          ),
          const SizedBox(height: 12),
          // Contact card.
          if (shop.ownerName.isNotEmpty ||
              shop.phone.isNotEmpty ||
              shop.address.isNotEmpty ||
              shop.note.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (shop.ownerName.isNotEmpty)
                    _ContactRow(Icons.person_outline, shop.ownerName),
                  if (shop.phone.isNotEmpty)
                    _ContactRow(Icons.phone_outlined, shop.phone),
                  if (shop.address.isNotEmpty)
                    _ContactRow(Icons.location_on_outlined, shop.address),
                  if (shop.note.isNotEmpty)
                    _ContactRow(Icons.sticky_note_2_outlined, shop.note),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Buying summary.
          ResponsiveCardGrid(
            cards: [
              MetricCard(label: 'Total bought', value: money.format(total)),
              MetricCard(
                  label: 'Bought · this month',
                  value: money.format(thisMonth)),
              MetricCard(label: 'Purchases', value: formatQty(count)),
              MetricCard(
                label: 'Last purchase',
                value: last == null ? '—' : prettyDate(last),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Record purchase'),
            onPressed: () =>
                showShopPurchaseSheet(context, ref, shopId: shopId),
          ),
          const SectionTitle('Purchase history'),
          if (purchases.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No purchases yet',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < purchases.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PurchaseRow(
                      purchase: purchases[i],
                      money: money,
                      salespersonName: purchases[i].salespersonId == null
                          ? null
                          : ledger
                                  .salesperson(purchases[i].salespersonId!)
                                  ?.name ??
                              '(former salesperson)',
                      onDelete: () => _deletePurchase(context, ref, purchases[i]),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: Icon(Icons.delete_outline, color: AppColors.danger),
            label: Text('Remove shop',
                style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(color: AppColors.danger),
            ),
            onPressed: () => _remove(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePurchase(
      BuildContext context, WidgetRef ref, ShopPurchase p) async {
    final ok = await confirm(
      context,
      title: 'Delete purchase',
      message: 'Remove this purchase record? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    await ref.read(repositoryProvider).deleteShopPurchase(p.id);
    if (context.mounted) showToast(context, 'Purchase deleted');
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Remove shop',
      message:
          'This deletes the shop and its purchase history. This cannot be undone.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    await ref.read(repositoryProvider).deleteShop(shopId);
    if (!context.mounted) return;
    showToast(context, 'Shop removed');
    Navigator.of(context).pop();
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ContactRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  final ShopPurchase purchase;
  final Money money;
  final String? salespersonName;
  final VoidCallback onDelete;
  const _PurchaseRow({
    required this.purchase,
    required this.money,
    required this.salespersonName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      prettyDate(purchase.date),
      if (salespersonName != null) 'by $salespersonName',
      if ((purchase.note ?? '').isNotEmpty) purchase.note!,
    ].join(' · ');

    return InkWell(
      onTap: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bought',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text(money.format(purchase.amount),
                style: tabularFigures.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.positive,
                )),
          ],
        ),
      ),
    );
  }
}

/// Colour used for a shop's loyalty segment.
Color segmentColor(ShopSegment s) => switch (s) {
      ShopSegment.reliable => AppColors.positive,
      ShopSegment.fresh => AppColors.warning,
      ShopSegment.regular => AppColors.muted,
      ShopSegment.inactive => AppColors.danger,
    };

/// A small pill showing a shop's loyalty segment (New / Regular / Reliable /
/// Inactive).
class ShopSegmentBadge extends StatelessWidget {
  final ShopSegment segment;
  const ShopSegmentBadge(this.segment, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = segmentColor(segment);
    return _Pill(text: segment.label, color: color);
  }
}

/// A pill marking the top-buying shop.
class TopBuyerBadge extends StatelessWidget {
  const TopBuyerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return _Pill(
      text: 'Top buyer',
      color: AppColors.positive,
      icon: Icons.star,
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const _Pill({required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
