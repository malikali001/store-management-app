import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/period_selector.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/period.dart';
import '../sheets/expense_sheet.dart';
import '../sheets/payment_sheet.dart';
import '../sheets/sale_sheet.dart';
import '../sheets/stockin_sheet.dart';
import 'salesperson_ledger_screen.dart';
import 'settings_screen.dart';

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
    final top = ledger.topSalespersons(period);

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
          const SectionTitle('Top salespersons'),
          if (top.isEmpty)
            const AppCard(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
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
        ],
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('Owed ${money.format(owed)}',
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            Text('Took ${money.format(taken)}',
                style: tabularFigures.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.muted),
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
