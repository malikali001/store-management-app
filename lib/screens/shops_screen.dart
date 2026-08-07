import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../sheets/shop_form.dart';
import 'shop_detail_screen.dart';
import 'shop_insights_screen.dart';

/// Shops — the store's external customers (retailers who buy to resell).
///
/// Its own page rather than a tab: reached from the Customers section on Home.
/// Salespersons (hired staff) live on the People tab and are a different thing
/// entirely.
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({super.key});

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(ledgerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shops'),
        actions: [
          IconButton(
            tooltip: 'Customer insights',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ShopInsightsScreen(),
            )),
          ),
          IconButton(
            tooltip: 'Add shop',
            icon: const Icon(Icons.add),
            onPressed: () => showShopForm(context, ref),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) => _buildList(ledger),
      ),
    );
  }

  Widget _buildList(Ledger ledger) {
    final money = ref.watch(moneyProvider);
    final now = DateTime.now();
    final topValue = ledger.topBoughtValue;

    final q = _query.trim().toLowerCase();
    var shops = ledger.shops.where((s) => !s.archived).toList();
    if (q.isNotEmpty) {
      shops = shops
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.ownerName.toLowerCase().contains(q) ||
              s.phone.toLowerCase().contains(q) ||
              s.address.toLowerCase().contains(q))
          .toList();
    }
    // Highest buyers first.
    shops.sort((a, b) =>
        ledger.totalBought(b.id).compareTo(ledger.totalBought(a.id)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search shops',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: shops.isEmpty
              ? EmptyState(
                  icon: Icons.storefront_outlined,
                  message: ledger.shops.where((s) => !s.archived).isEmpty
                      ? 'No shops yet. Tap + to add a customer shop.'
                      : 'No shops match your search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  // While searching, the list is a lookup tool — the insights
                  // header would only push the results down.
                  itemCount: shops.length + (q.isEmpty ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (q.isEmpty) {
                      if (index == 0) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: ShopInsightsHeadlines(title: 'Insights'),
                        );
                      }
                      index -= 1;
                    }
                    final s = shops[index];
                    final total = ledger.totalBought(s.id);
                    final segment = ledger.shopSegment(s.id, now);
                    final isTop = total > 0 && total == topValue;
                    return AppCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ShopDetailScreen(shopId: s.id),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                if (s.ownerName.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(s.ownerName,
                                      style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12)),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    ShopSegmentBadge(segment),
                                    if (isTop) const TopBuyerBadge(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Flexible so a large OS text scale wraps the amount
                          // rather than overflowing the card.
                          Flexible(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(money.format(total),
                                    textAlign: TextAlign.end,
                                    style: tabularFigures.copyWith(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('bought',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.muted),
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
