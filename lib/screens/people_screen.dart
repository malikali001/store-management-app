import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../sheets/salesperson_form.dart';
import '../sheets/shop_form.dart';
import 'salesperson_ledger_screen.dart';
import 'shop_detail_screen.dart';

/// Section 7.9 — people: external customers (Shops) and hired staff
/// (Salespersons), split into two segments on one screen.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

enum _PeopleTab { shops, staff }

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  _PeopleTab _tab = _PeopleTab.shops;

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(ledgerProvider);
    final isShops = _tab == _PeopleTab.shops;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: isShops ? 'Add shop' : 'Add salesperson',
            icon: const Icon(Icons.add),
            onPressed: () => isShops
                ? showShopForm(context, ref)
                : showSalespersonForm(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_PeopleTab>(
              segments: const [
                ButtonSegment(
                  value: _PeopleTab.shops,
                  label: Text('Shops'),
                  icon: Icon(Icons.storefront_outlined),
                ),
                ButtonSegment(
                  value: _PeopleTab.staff,
                  label: Text('Staff'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: ledgerAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (ledger) => isShops
                  ? _ShopsList(ledger: ledger)
                  : _StaffList(ledger: ledger),
            ),
          ),
        ],
      ),
    );
  }
}

/// External customers, ranked by how much they buy, with a loyalty badge.
class _ShopsList extends ConsumerStatefulWidget {
  final Ledger ledger;
  const _ShopsList({required this.ledger});

  @override
  ConsumerState<_ShopsList> createState() => _ShopsListState();
}

class _ShopsListState extends ConsumerState<_ShopsList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search shops',
              prefixIcon: const Icon(Icons.search),
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
                  itemCount: shops.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = shops[i];
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(money.format(total),
                                  style: tabularFigures.copyWith(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('bought',
                                  style: TextStyle(
                                      color: AppColors.muted, fontSize: 11)),
                            ],
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

/// Hired staff (salespersons), sorted by balance owed (highest first).
class _StaffList extends ConsumerStatefulWidget {
  final Ledger ledger;
  const _StaffList({required this.ledger});

  @override
  ConsumerState<_StaffList> createState() => _StaffListState();
}

class _StaffListState extends ConsumerState<_StaffList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = widget.ledger;
    final money = ref.watch(moneyProvider);

    final all = ledger.salespersons.where((s) => !s.archived).toList();
    final q = _query.trim().toLowerCase();
    var people = all;
    if (q.isNotEmpty) {
      people = all
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.phone.toLowerCase().contains(q))
          .toList();
    }
    people.sort((a, b) => ledger.balance(b.id).compareTo(ledger.balance(a.id)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search staff',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: people.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  message: all.isEmpty
                      ? 'No salespersons yet. Tap + to add one.'
                      : 'No staff match your search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = people[i];
                    final bal = ledger.balance(s.id);
                    return AppCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SalespersonLedgerScreen(salespersonId: s.id),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(s.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ),
                          Text(money.format(bal),
                              style: tabularFigures.copyWith(
                                fontWeight: FontWeight.w600,
                                color:
                                    bal > 0 ? AppColors.danger : AppColors.ink,
                              )),
                          const SizedBox(width: 8),
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
