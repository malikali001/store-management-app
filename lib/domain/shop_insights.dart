/// Shop (customer) performance insights — who buys most, who is growing, and
/// who has gone quiet and is worth a call.
///
/// The counterpart to [ProductInsights], but the available signals differ. A
/// [ShopPurchase] records only an **amount and a date** — no line items and no
/// cost — so there is no per-shop profit, margin, or unit volume to rank. Every
/// lens here is built from money bought, order count, and timing, which is what
/// the purchase log actually knows.
///
/// Pure Dart, derived from the purchase log. Nothing is stored; deleting a
/// purchase corrects every figure immediately.
library;

import 'ledger.dart';
import 'models.dart';
import 'period.dart';

/// One way of ranking customers. Each lens answers a single question the owner
/// might ask when deciding who to visit, chase, or look after.
enum ShopLens {
  /// Spent the most money.
  topBuyers,

  /// Placed the most separate orders.
  mostOrders,

  /// Highest average value per order.
  biggestOrders,

  /// Spending more lately than before.
  buyingMore,

  /// Spending less lately than before.
  buyingLess,

  /// Has a buying history but has not ordered in a long while.
  goneQuiet,

  /// On the books as a customer but has never bought anything.
  neverBought;

  /// Section heading on the insights screen.
  String get title => switch (this) {
        ShopLens.topBuyers => 'Top buyers',
        ShopLens.mostOrders => 'Most orders',
        ShopLens.biggestOrders => 'Biggest orders',
        ShopLens.buyingMore => 'Buying more',
        ShopLens.buyingLess => 'Buying less',
        ShopLens.goneQuiet => 'Gone quiet',
        ShopLens.neverBought => 'Never bought',
      };

  /// Short label used when a single shop is shown as a headline.
  String get shortLabel => switch (this) {
        ShopLens.topBuyers => 'Top buyer',
        ShopLens.mostOrders => 'Most orders',
        ShopLens.biggestOrders => 'Biggest orders',
        ShopLens.buyingMore => 'Buying more',
        ShopLens.buyingLess => 'Buying less',
        ShopLens.goneQuiet => 'Gone quiet',
        ShopLens.neverBought => 'Never bought',
      };

  /// One plain-language line explaining what the list means.
  String get hint => switch (this) {
        ShopLens.topBuyers => 'Spent the most in this period.',
        ShopLens.mostOrders => 'Came back the most times in this period.',
        ShopLens.biggestOrders =>
          'Largest average order in this period. Fewer visits can still mean '
              'more money.',
        ShopLens.buyingMore => 'Spending more lately than in the stretch before.',
        ShopLens.buyingLess =>
          'Spending less lately than in the stretch before. Worth asking why.',
        ShopLens.goneQuiet =>
          'Used to buy, but nothing for a long while. Longest silence first.',
        ShopLens.neverBought =>
          'On your books but has never ordered. Longest wait first.',
      };

  /// True for the lenses that report a problem rather than a success, so the UI
  /// can colour them as "needs attention" instead of "doing well".
  bool get needsAttention =>
      this == ShopLens.buyingLess ||
      this == ShopLens.goneQuiet ||
      this == ShopLens.neverBought;
}

/// Everything derived about one shop, over one period.
///
/// [bought] and [orders] are scoped to the period. The relationship figures
/// ([totalBought], [lastPurchaseDate], [daysSinceLastPurchase], [segment]) are
/// always all-time — "this customer has gone quiet" is a fact about now, not
/// about the selected window.
class ShopStat {
  final Shop shop;

  /// Money the shop bought within the period.
  final int bought;

  /// Number of separate purchases within the period.
  final int orders;

  /// Money bought in the most recent [ShopInsights.trendWindowDays].
  final int recentBought;

  /// Money bought in the equally long window immediately before that.
  final int priorBought;

  /// Money the shop has ever bought.
  final int totalBought;

  /// How many purchases the shop has ever made.
  final int totalOrders;

  /// Date of the most recent purchase, or null if it has never bought.
  final String? lastPurchaseDate;

  /// Whole days from the last purchase to the end of the measured window, or
  /// null if the shop has never bought.
  final int? daysSinceLastPurchase;

  /// Days since the shop was added as a customer.
  final int daysSinceAdded;

  /// The loyalty segment (New / Regular / Reliable / Inactive).
  final ShopSegment segment;

  const ShopStat({
    required this.shop,
    required this.bought,
    required this.orders,
    required this.recentBought,
    required this.priorBought,
    required this.totalBought,
    required this.totalOrders,
    required this.lastPurchaseDate,
    required this.daysSinceLastPurchase,
    required this.daysSinceAdded,
    required this.segment,
  });

  /// Average order value within the period (0 when there were no orders).
  int get averageOrder => orders > 0 ? (bought / orders).round() : 0;

  /// Change in spend between the previous window and the recent one.
  int get trendDelta => recentBought - priorBought;

  /// Whether this shop has ever bought anything.
  bool get hasEverBought => totalOrders > 0;

  /// Nothing to say about a shop that has never bought and was just added.
  bool get isIdle => !hasEverBought && bought == 0;
}

/// Ranked customer insights for one [Period], built in a single pass over the
/// purchase log.
class ShopInsights {
  final Period period;

  /// One entry per live (non-archived) shop.
  final List<ShopStat> stats;

  /// Length of the recent/previous windows compared by [ShopLens.buyingMore]
  /// and [ShopLens.buyingLess].
  final int trendWindowDays;

  /// The last day measured — the period's end, or today for an all-time period.
  final String windowEnd;

  const ShopInsights({
    required this.period,
    required this.stats,
    required this.trendWindowDays,
    required this.windowEnd,
  });

  /// Silence longer than this counts as "gone quiet". Matches the recency the
  /// ledger already uses to decide a shop is still dependable, so the two
  /// notions of "recent" agree.
  static const int quietAfterDays = Ledger.loyalRecencyDays;

  /// How many days each trend window covers, per period.
  ///
  /// Deliberately wider than the product windows: a shop orders every few weeks,
  /// not every day, so a fortnight often contains no order at all and would make
  /// every customer look like they had stopped buying.
  static int trendWindowFor(PeriodKind kind) => switch (kind) {
        PeriodKind.month => 30,
        PeriodKind.quarter => 60,
        PeriodKind.allTime => 90,
      };

  /// Derives every figure from [ledger] for [period]. [now] is the device-local
  /// clock — passed in so results are deterministic and testable.
  static ShopInsights build(Ledger ledger, Period period, DateTime now) {
    final todayIso = Period.fmtDate(now);
    final trendWindow = trendWindowFor(period.kind);

    var windowEnd = period.to ?? todayIso;
    if (windowEnd.compareTo(todayIso) > 0) windowEnd = todayIso;
    final recentFrom = Period.shiftDays(windowEnd, -(trendWindow - 1));
    final priorTo = Period.shiftDays(recentFrom, -1);
    final priorFrom = Period.shiftDays(priorTo, -(trendWindow - 1));

    final bought = <String, int>{};
    final orders = <String, int>{};
    final recent = <String, int>{};
    final prior = <String, int>{};
    final total = <String, int>{};
    final totalCount = <String, int>{};
    final lastDate = <String, String>{};

    void add(Map<String, int> m, String key, int delta) =>
        m[key] = (m[key] ?? 0) + delta;

    for (final p in ledger.shopPurchases) {
      add(total, p.shopId, p.amount);
      add(totalCount, p.shopId, 1);

      final last = lastDate[p.shopId];
      if (last == null || p.date.compareTo(last) > 0) lastDate[p.shopId] = p.date;

      if (period.contains(p.date)) {
        add(bought, p.shopId, p.amount);
        add(orders, p.shopId, 1);
      }
      if (p.date.compareTo(recentFrom) >= 0 &&
          p.date.compareTo(windowEnd) <= 0) {
        add(recent, p.shopId, p.amount);
      } else if (p.date.compareTo(priorFrom) >= 0 &&
          p.date.compareTo(priorTo) <= 0) {
        add(prior, p.shopId, p.amount);
      }
    }

    final stats = <ShopStat>[];
    for (final s in ledger.shops) {
      if (s.archived) continue;
      final last = lastDate[s.id];
      stats.add(ShopStat(
        shop: s,
        bought: bought[s.id] ?? 0,
        orders: orders[s.id] ?? 0,
        recentBought: recent[s.id] ?? 0,
        priorBought: prior[s.id] ?? 0,
        totalBought: total[s.id] ?? 0,
        totalOrders: totalCount[s.id] ?? 0,
        lastPurchaseDate: last,
        daysSinceLastPurchase:
            last == null ? null : Period.daysBetween(last, windowEnd),
        daysSinceAdded: Period.daysBetween(
            Period.fmtDate(DateTime.fromMillisecondsSinceEpoch(s.createdAt)),
            windowEnd),
        // The ledger owns what a segment means; don't re-derive it here.
        segment: ledger.shopSegment(s.id, now),
      ));
    }

    return ShopInsights(
      period: period,
      stats: stats,
      trendWindowDays: trendWindow,
      windowEnd: windowEnd,
    );
  }

  /// True when there is nothing to say yet (no shop has ever bought).
  bool get isEmpty => stats.every((s) => s.isIdle);

  // ---- Store-wide customer figures (for the dashboard) ---------------------

  /// Money all customers bought within the period.
  int get boughtInPeriod => stats.fold(0, (sum, s) => sum + s.bought);

  /// Money all customers have ever bought.
  int get boughtAllTime => stats.fold(0, (sum, s) => sum + s.totalBought);

  /// How many live customers are on the books.
  int get customerCount => stats.length;

  /// How many customers bought at least once within the period.
  int get activeCount => stats.where((s) => s.bought > 0).length;

  /// How many customers have gone quiet — worth a call.
  int get quietCount => ranked(ShopLens.goneQuiet).length;

  /// How many customers are new to the shop.
  int get newCount =>
      stats.where((s) => s.segment == ShopSegment.fresh).length;

  /// Shops ranked for [lens], most notable first. Shops the lens has nothing to
  /// say about are left out, so an empty list honestly means "nothing to report".
  List<ShopStat> ranked(ShopLens lens) => switch (lens) {
        // Money in, this period. Ties broken by order count.
        ShopLens.topBuyers => _pick(
            (s) => s.bought > 0,
            (a, b) => _cmp(b.bought, a.bought, () => _cmp(b.orders, a.orders)),
          ),

        // Visit frequency. Ties broken by money.
        ShopLens.mostOrders => _pick(
            (s) => s.orders > 0,
            (a, b) => _cmp(b.orders, a.orders, () => _cmp(b.bought, a.bought)),
          ),

        // Value per visit. Needs at least one order to have an average at all.
        ShopLens.biggestOrders => _pick(
            (s) => s.orders > 0,
            (a, b) => _cmp(
                b.averageOrder, a.averageOrder, () => _cmp(b.bought, a.bought)),
          ),

        // Growing. Must be buying now, not merely quiet before.
        ShopLens.buyingMore => _pick(
            (s) => s.recentBought > 0 && s.trendDelta > 0,
            (a, b) => _cmp(b.trendDelta, a.trendDelta,
                () => _cmp(b.recentBought, a.recentBought)),
          ),

        // Shrinking. Must have been buying before, or there is no decline to see.
        ShopLens.buyingLess => _pick(
            (s) => s.priorBought > 0 && s.trendDelta < 0,
            (a, b) => _cmp(a.trendDelta, b.trendDelta,
                () => _cmp(b.priorBought, a.priorBought)),
          ),

        // Silent customers, longest silence first. Money at stake breaks ties.
        ShopLens.goneQuiet => _pick(
            (s) =>
                s.hasEverBought &&
                (s.daysSinceLastPurchase ?? 0) > quietAfterDays,
            (a, b) => _cmp(b.daysSinceLastPurchase ?? 0,
                a.daysSinceLastPurchase ?? 0, () => _cmp(b.totalBought, a.totalBought)),
          ),

        // Never ordered, longest wait first.
        ShopLens.neverBought => _pick(
            (s) => !s.hasEverBought,
            (a, b) => _cmp(b.daysSinceAdded, a.daysSinceAdded),
          ),
      };

  /// The single most notable shop for [lens], or null when there is nothing to
  /// report.
  ShopStat? top(ShopLens lens) {
    final list = ranked(lens);
    return list.isEmpty ? null : list.first;
  }

  /// The lenses shown as one-line headlines above the shops list: who matters
  /// most, who is growing, who is slipping, who has gone silent.
  static const List<ShopLens> headlineLenses = [
    ShopLens.topBuyers,
    ShopLens.buyingMore,
    ShopLens.buyingLess,
    ShopLens.goneQuiet,
  ];

  /// [headlineLenses] paired with one shop each, empty lenses removed.
  ///
  /// As with products, one shop often tops several lenses at once, so each lens
  /// takes its highest-ranked shop that another lens has not already claimed —
  /// four different customers rather than the same name four times.
  List<(ShopLens, ShopStat)> get headlines {
    final used = <String>{};
    final out = <(ShopLens, ShopStat)>[];
    for (final lens in headlineLenses) {
      for (final s in ranked(lens)) {
        if (used.add(s.shop.id)) {
          out.add((lens, s));
          break;
        }
      }
    }
    return out;
  }

  List<ShopStat> _pick(
      bool Function(ShopStat) keep, int Function(ShopStat, ShopStat) order) {
    // `List.sort` is not stable, so every comparator ends on shop identity.
    return stats.where(keep).toList()
      ..sort((a, b) {
        final c = order(a, b);
        return c != 0 ? c : _byIdentity(a, b);
      });
  }

  static int _byIdentity(ShopStat a, ShopStat b) {
    final n =
        a.shop.name.toLowerCase().compareTo(b.shop.name.toLowerCase());
    return n != 0 ? n : a.shop.id.compareTo(b.shop.id);
  }

  static int _cmp(int a, int b, [int Function()? then]) {
    final c = a.compareTo(b);
    if (c != 0 || then == null) return c;
    return then();
  }
}
