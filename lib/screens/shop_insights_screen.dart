import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/period_selector.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/period.dart';
import '../domain/shop_insights.dart';
import 'shop_detail_screen.dart';

/// Customer performance insights — who buys most, who is growing, and who has
/// gone quiet. Reached from the Shops tab on People.
///
/// One lens at a time, mirroring the product insights screen.
class ShopInsightsScreen extends ConsumerStatefulWidget {
  /// The lens selected on open — tapping a headline lands on that list.
  final ShopLens initialLens;
  const ShopInsightsScreen({super.key, this.initialLens = ShopLens.topBuyers});

  @override
  ConsumerState<ShopInsightsScreen> createState() => _ShopInsightsScreenState();
}

class _ShopInsightsScreenState extends ConsumerState<ShopInsightsScreen> {
  late ShopLens _lens = widget.initialLens;

  @override
  Widget build(BuildContext context) {
    final insightsAsync = ref.watch(shopInsightsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Customer insights')),
      body: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (insights) => _buildBody(insights),
      ),
    );
  }

  Widget _buildBody(ShopInsights insights) {
    final money = ref.watch(moneyProvider);
    final ranked = insights.ranked(_lens);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PeriodSelector(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lens in ShopLens.values)
                ChoiceChip(
                  label: Text(lens.title),
                  selected: _lens == lens,
                  showCheckmark: false,
                  backgroundColor: AppColors.surface,
                  selectedColor: lens.needsAttention
                      ? AppColors.warning
                      : AppColors.positive,
                  side: BorderSide(color: AppColors.hairline),
                  labelStyle: TextStyle(
                    color: _lens == lens ? Colors.white : AppColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                  onSelected: (_) => setState(() => _lens = lens),
                ),
            ],
          ),
          SectionTitle(_lens.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(_lens.hint,
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          if (ranked.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  insights.isEmpty
                      ? 'Record a shop purchase to see how your customers are '
                          'doing.'
                      : 'Nothing to report here for this period.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < ranked.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ShopInsightRow(
                      rank: i + 1,
                      lens: _lens,
                      stat: ranked[i],
                      money: money,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(_footnote(insights),
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  /// States the basis of the figures, so a surprising ranking can be traced.
  String _footnote(ShopInsights insights) {
    final label = PeriodSelector.label(insights.period.kind).toLowerCase();
    return switch (_lens) {
      ShopLens.buyingMore || ShopLens.buyingLess =>
        'Compares the last ${insights.trendWindowDays} days with the '
            '${insights.trendWindowDays} before them, regardless of the period '
            'above — a shop orders every few weeks, so a shorter window would '
            'read as a slump.',
      ShopLens.goneQuiet =>
        'Counts from each shop\'s most recent order, all-time. A shop is quiet '
            'after ${ShopInsights.quietAfterDays} days without one.',
      ShopLens.neverBought => 'Counts from the day the shop was added.',
      _ => 'Covers the selected period ($label). Totals and last-order dates '
          'are always all-time.',
    };
  }
}

/// Customer performance at a glance: who buys most, who is growing, who is
/// slipping, who has gone silent. One headline per lens, each opening that lens
/// on [ShopInsightsScreen].
///
/// Used on the dashboard and above the shops list. Renders nothing at all when
/// no customer has bought yet, so it never occupies space with filler.
class ShopInsightsHeadlines extends ConsumerWidget {
  /// Shown above the card. Pass null to render the rows alone.
  final String? title;
  const ShopInsightsHeadlines({super.key, this.title = 'Customer insights'});

  void _open(BuildContext context, ShopLens lens) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShopInsightsScreen(initialLens: lens),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final insights = ref.watch(shopInsightsProvider).valueOrNull;
    if (insights == null || insights.isEmpty) return const SizedBox.shrink();

    final headlines = insights.headlines;
    if (headlines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          SectionTitle(
            title!,
            trailing: TextButton(
              onPressed: () => _open(context, ShopLens.topBuyers),
              child: const Text('See all'),
            ),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < headlines.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ShopHeadlineRow(
                  lens: headlines[i].$1,
                  stat: headlines[i].$2,
                  money: money,
                  onTap: () => _open(context, headlines[i].$1),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One "Top buyer · Metro Mart — 338,000" line.
class _ShopHeadlineRow extends StatelessWidget {
  final ShopLens lens;
  final ShopStat stat;
  final Money money;
  final VoidCallback onTap;
  const _ShopHeadlineRow({
    required this.lens,
    required this.stat,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lens.shortLabel,
                      style: TextStyle(
                          color: lens.needsAttention
                              ? AppColors.warning
                              : AppColors.muted,
                          fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(stat.shop.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(shopInsightMetric(lens, stat, money),
                  textAlign: TextAlign.end,
                  style: tabularFigures.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// One ranked shop, with the figure that put it on this list.
class _ShopInsightRow extends StatelessWidget {
  final int rank;
  final ShopLens lens;
  final ShopStat stat;
  final Money money;
  const _ShopInsightRow({
    required this.rank,
    required this.lens,
    required this.stat,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ShopDetailScreen(shopId: stat.shop.id),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('$rank',
                  style: tabularFigures.copyWith(
                      color: AppColors.muted, fontSize: 13)),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stat.shop.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(shopInsightDetail(lens, stat, money),
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Flexible, so a long figure at a large OS text scale wraps instead
            // of pushing the row off a narrow screen.
            Flexible(
              flex: 2,
              child: Text(shopInsightMetric(lens, stat, money),
                  textAlign: TextAlign.end,
                  style: tabularFigures.copyWith(
                    fontWeight: FontWeight.w600,
                    color: lens.needsAttention
                        ? AppColors.warning
                        : AppColors.ink,
                  )),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The single figure that earned a shop its place on [lens]'s list.
String shopInsightMetric(ShopLens lens, ShopStat s, Money money) =>
    switch (lens) {
      ShopLens.topBuyers => money.format(s.bought),
      ShopLens.mostOrders => _orders(s.orders),
      ShopLens.biggestOrders => money.format(s.averageOrder),
      ShopLens.buyingMore => money.signed(s.trendDelta),
      ShopLens.buyingLess => money.signed(s.trendDelta),
      ShopLens.goneQuiet => _days(s.daysSinceLastPurchase ?? 0),
      ShopLens.neverBought => _days(s.daysSinceAdded),
    };

/// The supporting line under the shop name.
String shopInsightDetail(ShopLens lens, ShopStat s, Money money) =>
    switch (lens) {
      ShopLens.topBuyers =>
        '${_orders(s.orders)} · ${money.format(s.averageOrder)} each',
      ShopLens.mostOrders => '${money.format(s.bought)} in total',
      ShopLens.biggestOrders =>
        '${_orders(s.orders)} · ${money.format(s.bought)} in total',
      ShopLens.buyingMore || ShopLens.buyingLess =>
        '${money.format(s.priorBought)} → ${money.format(s.recentBought)}',
      ShopLens.goneQuiet => s.lastPurchaseDate == null
          ? 'Never ordered'
          : 'Last order ${prettyDate(s.lastPurchaseDate!)} · '
              '${money.format(s.totalBought)} all-time',
      ShopLens.neverBought => 'Added ${prettyDate(_addedIso(s))}',
    };

/// The day a shop was added, as an ISO date for [prettyDate].
String _addedIso(ShopStat s) => Period.fmtDate(
    DateTime.fromMillisecondsSinceEpoch(s.shop.createdAt));

String _orders(int n) => '${formatQty(n)} ${n == 1 ? 'order' : 'orders'}';

String _days(int n) => '$n ${n == 1 ? 'day' : 'days'}';
