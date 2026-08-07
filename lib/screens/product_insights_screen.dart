import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/period_selector.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/models.dart';
import '../domain/product_insights.dart';
import 'product_detail_screen.dart';

/// Product performance insights — which products earn, which sit, and which
/// need reordering. Reached from the Home dashboard.
///
/// One lens at a time, so the screen answers a single question clearly rather
/// than showing eight lists at once.
class ProductInsightsScreen extends ConsumerStatefulWidget {
  /// The lens selected on open — tapping a Home headline lands on that list.
  final InsightLens initialLens;
  const ProductInsightsScreen({super.key, this.initialLens = InsightLens.fastMovers});

  @override
  ConsumerState<ProductInsightsScreen> createState() =>
      _ProductInsightsScreenState();
}

class _ProductInsightsScreenState extends ConsumerState<ProductInsightsScreen> {
  late InsightLens _lens = widget.initialLens;

  @override
  Widget build(BuildContext context) {
    final insightsAsync = ref.watch(productInsightsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Product insights')),
      body: insightsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (insights) => _buildBody(insights),
      ),
    );
  }

  Widget _buildBody(ProductInsights insights) {
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
              for (final lens in InsightLens.values)
                ChoiceChip(
                  label: Text(lens.title),
                  selected: _lens == lens,
                  showCheckmark: false,
                  backgroundColor: AppColors.surface,
                  selectedColor: _tone(lens),
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
                      ? 'Record a sale to see how your products are doing.'
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
                    _InsightRow(
                      rank: i + 1,
                      lens: _lens,
                      stat: ranked[i],
                      money: money,
                      insights: insights,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _footnote(insights),
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Explains, in plain language, the window every figure was measured over —
  /// so a surprising ranking can always be traced back to its basis.
  String _footnote(ProductInsights insights) {
    final label = PeriodSelector.label(insights.period.kind).toLowerCase();
    final base = 'Sales figures cover the selected period ($label). '
        'Stock is always the current count.';
    return switch (_lens) {
      InsightLens.trending =>
        '$base Trending compares the last ${insights.trendWindowDays} days '
            'with the ${insights.trendWindowDays} before them.',
      InsightLens.restock =>
        '$base Days left assumes each product keeps selling at its average '
            'rate over the last ${insights.spanDays} '
            '${insights.spanDays == 1 ? 'day' : 'days'} of trading.',
      _ => base,
    };
  }
}

/// One ranked product, with the figure that put it on this list.
class _InsightRow extends StatelessWidget {
  final int rank;
  final InsightLens lens;
  final ProductStat stat;
  final Money money;
  final ProductInsights insights;
  const _InsightRow({
    required this.rank,
    required this.lens,
    required this.stat,
    required this.money,
    required this.insights,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: stat.product.id),
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
                  Text(productLabel(stat.product),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(insightDetail(lens, stat, money),
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Flexible, so a long figure at a large OS text scale wraps instead
            // of pushing the row off a narrow screen.
            Flexible(
              flex: 2,
              child: Text(insightMetric(lens, stat, money),
                  textAlign: TextAlign.end,
                  style: tabularFigures.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _metricColor(lens, stat),
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

/// "Cotton tee · M" — name plus size, or just the name for a sizeless item.
String productLabel(Product p) {
  final size = p.size.trim();
  return size.isEmpty ? p.name : '${p.name} · $size';
}

/// The single figure that earned a product its place on [lens]'s list.
String insightMetric(InsightLens lens, ProductStat s, Money money) =>
    switch (lens) {
      InsightLens.fastMovers => _units(s.units),
      InsightLens.bestSellers => money.format(s.revenue),
      InsightLens.topProfit => money.format(s.margin),
      InsightLens.bestMargin => '${s.marginPct}%',
      InsightLens.thinMargin => '${s.marginPct}%',
      InsightLens.trending => '+${formatQty(s.trendDelta)}',
      InsightLens.restock => _cover(s),
      InsightLens.slowMovers => _units(s.units),
    };

/// The supporting line under the product name: the context that makes the
/// headline figure meaningful.
String insightDetail(InsightLens lens, ProductStat s, Money money) =>
    switch (lens) {
      InsightLens.fastMovers => '${money.format(s.revenue)} in sales',
      InsightLens.bestSellers => '${_units(s.units)} sold',
      InsightLens.topProfit => '${s.marginPct}% of sales kept',
      InsightLens.bestMargin => '${money.format(s.margin)} on '
          '${money.format(s.revenue)} of sales',
      InsightLens.thinMargin => '${money.format(s.margin)} on '
          '${money.format(s.revenue)} of sales',
      InsightLens.trending =>
        '${formatQty(s.priorUnits)} → ${formatQty(s.recentUnits)} units',
      InsightLens.restock => '${formatQty(s.stock)} left · '
          '${_units(s.units)} sold',
      InsightLens.slowMovers =>
        '${formatQty(s.stock)} in stock · ${money.format(s.stockValue)} tied up',
    };

String _units(int n) => '${formatQty(n)} ${n == 1 ? 'unit' : 'units'}';

/// Days of stock left at the measured rate, phrased for a shopkeeper.
String _cover(ProductStat s) {
  final cover = s.daysOfCover;
  if (cover == null) return '—';
  if (s.stock <= 0) return 'Out';
  if (cover < 1) return '<1 day';
  final days = cover.round();
  return '$days ${days == 1 ? 'day' : 'days'}';
}

/// Green where the news is good, warning/danger where it needs attention.
Color _metricColor(InsightLens lens, ProductStat s) => switch (lens) {
      InsightLens.fastMovers => AppColors.ink,
      InsightLens.bestSellers => AppColors.ink,
      InsightLens.topProfit => AppColors.positive,
      InsightLens.bestMargin => AppColors.positive,
      InsightLens.trending => AppColors.positive,
      InsightLens.restock => AppColors.warning,
      InsightLens.slowMovers => AppColors.warning,
      InsightLens.thinMargin =>
        s.margin < 0 ? AppColors.danger : AppColors.warning,
    };

/// Chip fill for a selected lens: the problem lenses read as "needs attention".
Color _tone(InsightLens lens) =>
    lens.needsAttention ? AppColors.warning : AppColors.positive;
