import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/period_selector.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/period.dart';
import '../domain/product_insights.dart';
import '../domain/shop_insights.dart';
import '../sheets/expense_sheet.dart';
import '../sheets/payment_sheet.dart';
import '../sheets/sale_sheet.dart';
import '../sheets/stockin_sheet.dart';
import 'product_insights_screen.dart';
import 'salesperson_ledger_screen.dart';
import 'settings_screen.dart';
import 'shop_insights_screen.dart';
import 'shops_screen.dart';

/// Section 7.1 — dashboard.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(ledgerProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(settings.storeName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _HomeBody(ledger: ledger),
      ),
    );
  }
}

/// How many salespersons the dashboard lists. Just the leaders — the People tab
/// ranks everyone by balance, and Reports ranks everyone by goods taken.
const _homeTopSalespersons = 3;

// The dashboard carries several "See all" links. They are keyed so tests (and
// anyone reading a failure) can name the one they mean instead of relying on
// which happens to come first in the tree.
const seeAllSalespersonsKey = Key('see_all_salespersons');
const seeAllProductsKey = Key('see_all_products');
const seeAllCustomersKey = Key('see_all_customers');

class _HomeBody extends ConsumerWidget {
  final Ledger ledger;
  const _HomeBody({required this.ledger});

  String _periodLabel(PeriodKind kind) =>
      PeriodSelector.label(kind).toLowerCase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final period = ref.watch(periodProvider);
    final kind = ref.watch(periodKindProvider);
    final periodLabel = _periodLabel(kind);

    final cash = ledger.cashOnHand;
    final owed = ledger.totalOwed;
    final profit = ledger.netProfitInPeriod(period);
    final expenses = ledger.expensesInPeriod(period);
    final lowStockCount = ledger.lowStockProducts().length;
    // Home shows only the leaders; Reports' "Who sells more" has the full
    // ranking, so nothing is lost by keeping the dashboard short.
    final top =
        ledger.topSalespersons(period).take(_homeTopSalespersons).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PeriodSelector(),
          const SizedBox(height: 16),
          ResponsiveCardGrid(
            cards: [
              MetricCard(
                label: 'Cash on hand',
                value: money.format(cash),
                valueColor: cash < 0 ? AppColors.danger : null,
              ),
              MetricCard(
                label: 'Stock value',
                value: money.format(ledger.stockValue),
              ),
              MetricCard(
                label: 'Owed to you',
                value: money.format(owed),
                valueColor: AppColors.danger,
              ),
              MetricCard(
                label: 'Profit · $periodLabel',
                value: money.format(profit),
                valueColor: profit < 0 ? AppColors.danger : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(
                text: 'Expenses · $periodLabel ${money.format(expenses)}',
                color: AppColors.danger,
              ),
              InfoChip(
                text: 'Low stock · $lowStockCount '
                    '${lowStockCount == 1 ? 'item' : 'items'}',
                color: AppColors.warning,
              ),
            ],
          ),
          const SectionTitle('Quick actions'),
          _QuickActions(),
          SectionTitle(
            'Top salespersons',
            trailing: TextButton(
              key: seeAllSalespersonsKey,
              // The full list, ranked by what each owes, is the People tab.
              onPressed: () => ref.read(selectedTabProvider.notifier).state =
                  AppTab.people,
              child: const Text('See all'),
            ),
          ),
          if (top.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('No sales in this period',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ),
            )
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _TopRow(
                      name: top[i].key.name,
                      owed: ledger.balance(top[i].key.id),
                      taken: top[i].value,
                      money: money,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SalespersonLedgerScreen(
                              salespersonId: top[i].key.id),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const _ProductInsights(),
          const _Customers(),
        ],
      ),
    );
  }
}

/// Section 7.1 — customers (shops) at a glance, and the way in to the Shops
/// page. Shop purchases are a separate log from the salesperson ledger, so
/// these figures stand on their own and never mix into cash or owed.
class _Customers extends ConsumerWidget {
  const _Customers();

  void _openShops(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShopsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final kind = ref.watch(periodKindProvider);
    final periodLabel = PeriodSelector.label(kind).toLowerCase();
    final insights = ref.watch(shopInsightsProvider).valueOrNull;
    if (insights == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Customers',
          trailing: TextButton(
            key: seeAllCustomersKey,
            onPressed: () => _openShops(context),
            child: const Text('See all'),
          ),
        ),
        if (insights.customerCount == 0)
          AppCard(
            onTap: () => _openShops(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No customer shops yet. Add one to track who buys from you.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          )
        else ...[
          ResponsiveCardGrid(
            narrowColumns: 2,
            wideColumns: 3,
            cards: [
              MetricCard(
                label: 'Bought · $periodLabel',
                value: money.format(insights.boughtInPeriod),
              ),
              MetricCard(
                label: 'Shops',
                value: formatQty(insights.customerCount),
              ),
              // On an all-time period this would just repeat the first card.
              if (kind != PeriodKind.allTime)
                MetricCard(
                  label: 'Bought · all time',
                  value: money.format(insights.boughtAllTime),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(
                text: 'Active · $periodLabel ${insights.activeCount} of '
                    '${insights.customerCount}',
                color: AppColors.positive,
                onTap: () => _openShops(context),
              ),
              if (insights.newCount > 0)
                InfoChip(
                  text: 'New · ${insights.newCount}',
                  color: AppColors.positive,
                  onTap: () => _open(context, ShopLens.topBuyers),
                ),
              if (insights.quietCount > 0)
                InfoChip(
                  text: 'Gone quiet · ${insights.quietCount}',
                  color: AppColors.warning,
                  onTap: () => _open(context, ShopLens.goneQuiet),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Renders nothing until a customer has actually bought something.
          const ShopInsightsHeadlines(title: null),
        ],
      ],
    );
  }

  void _open(BuildContext context, ShopLens lens) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShopInsightsScreen(initialLens: lens),
    ));
  }
}

/// Section 7.1 — product performance at a glance: what moves, what earns, what
/// to reorder, what is picking up. One headline per lens; the full ranked lists
/// live on [ProductInsightsScreen].
class _ProductInsights extends ConsumerWidget {
  const _ProductInsights();

  void _open(BuildContext context, InsightLens lens) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductInsightsScreen(initialLens: lens),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final insights = ref.watch(productInsightsProvider).valueOrNull;
    if (insights == null) return const SizedBox.shrink();

    final headlines = insights.headlines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Product insights',
          trailing: TextButton(
            key: seeAllProductsKey,
            onPressed: () => _open(context, InsightLens.fastMovers),
            child: const Text('See all'),
          ),
        ),
        if (headlines.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Record a sale to see which products earn the most.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < headlines.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _HeadlineRow(
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

/// One "Fast mover · Cotton tee · M — 40 units" line.
class _HeadlineRow extends StatelessWidget {
  final InsightLens lens;
  final ProductStat stat;
  final Money money;
  final VoidCallback onTap;
  const _HeadlineRow({
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
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(productLabel(stat.product),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
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

class _TopRow extends StatelessWidget {
  final String name;
  final int owed;
  final int taken;
  final Money money;
  final VoidCallback onTap;
  const _TopRow({
    required this.name,
    required this.owed,
    required this.taken,
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
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('Owed ${money.format(owed)}',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Flexible so a large OS text scale wraps the amount rather than
            // overflowing the row on a narrow screen.
            Flexible(
              flex: 2,
              child: Text('Took ${money.format(taken)}',
                  textAlign: TextAlign.end,
                  style: tabularFigures.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.positive),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // 2×2 on phones (comfortable tap targets), 4-across on wider screens.
    return ResponsiveCardGrid(
      narrowColumns: 2,
      wideColumns: 4,
      breakpoint: 480,
      cards: [
        action(Icons.point_of_sale, 'New sale',
            () => showSaleSheet(context, ref)),
        action(Icons.add_box_outlined, 'Stock in',
            () => showStockInSheet(context, ref)),
        action(Icons.payments_outlined, 'Record payment',
            () => showPaymentSheet(context, ref)),
        action(Icons.receipt_long_outlined, 'Expense',
            () => showExpenseSheet(context, ref)),
      ],
    );
  }
}
