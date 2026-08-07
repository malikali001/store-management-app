/// Product performance insights — which products earn, which sit, which need
/// reordering (Section 6.7's rankings, extended from salespersons to products).
///
/// Pure Dart. Like everything else in the domain layer, every figure here is
/// derived by summing transactions, so deleting an entry corrects the insights
/// immediately. Nothing is stored.
///
/// All money figures use the price **snapshots** on the transaction lines, so a
/// later price edit never rewrites what a product actually earned.
library;

import 'ledger.dart';
import 'models.dart';
import 'period.dart';

/// One way of ranking the catalog. Each lens answers a single question the
/// owner might ask when deciding what to buy, push, or discount.
enum InsightLens {
  /// Most units sold — what moves off the shelf.
  fastMovers,

  /// Most revenue — what brings in the most money.
  bestSellers,

  /// Biggest gross margin in money terms.
  topProfit,

  /// Highest margin as a share of sales.
  bestMargin,

  /// Selling faster now than in the stretch before.
  trending,

  /// Real demand, little stock left.
  restock,

  /// Barely selling while stock sits on the shelf.
  slowMovers,

  /// Lowest margin as a share of sales (including sales at a loss).
  thinMargin;

  /// Section heading on the insights screen.
  String get title => switch (this) {
        InsightLens.fastMovers => 'Fast movers',
        InsightLens.bestSellers => 'Best sellers',
        InsightLens.topProfit => 'Most profit',
        InsightLens.bestMargin => 'Best margin',
        InsightLens.trending => 'Trending up',
        InsightLens.restock => 'Restock soon',
        InsightLens.slowMovers => 'Slow movers',
        InsightLens.thinMargin => 'Thin margin',
      };

  /// Short label used when a single product is shown as a headline on Home.
  String get shortLabel => switch (this) {
        InsightLens.fastMovers => 'Fast mover',
        InsightLens.bestSellers => 'Best seller',
        InsightLens.topProfit => 'Most profit',
        InsightLens.bestMargin => 'Best margin',
        InsightLens.trending => 'Trending up',
        InsightLens.restock => 'Restock soon',
        InsightLens.slowMovers => 'Slow mover',
        InsightLens.thinMargin => 'Thin margin',
      };

  /// One plain-language line explaining what the list means.
  String get hint => switch (this) {
        InsightLens.fastMovers => 'Most units sold in this period.',
        InsightLens.bestSellers => 'Most money taken in this period.',
        InsightLens.topProfit =>
          'Most margin earned — sell price less cost, on what sold.',
        InsightLens.bestMargin =>
          'Best margin for every unit of money sold. Small sellers can win here.',
        InsightLens.trending =>
          'Selling faster now than in the stretch before it.',
        InsightLens.restock =>
          'Still selling, but stock is nearly gone. Buy these first.',
        InsightLens.slowMovers =>
          'Selling least while stock sits. Money tied up on the shelf.',
        InsightLens.thinMargin =>
          'Lowest margin for every unit of money sold. Check the buy price.',
      };

  /// True for the lenses that report a problem rather than a success, so the UI
  /// can colour them as "needs attention" instead of "doing well".
  bool get needsAttention =>
      this == InsightLens.restock ||
      this == InsightLens.slowMovers ||
      this == InsightLens.thinMargin;
}

/// Everything derived about one product, over one period.
///
/// Sales figures ([units], [revenue], [cogs]) are scoped to the period.
/// [stock] is always the **current** stock — a past period cannot tell you what
/// is on the shelf right now, and reordering decisions need today's count.
class ProductStat {
  final Product product;

  /// Net units sold in the period (sale lines less return lines).
  final int units;

  /// Net sell value in the period, from the `unit_sell` snapshots.
  final int revenue;

  /// Net cost basis of those units, from the `unit_buy` snapshots.
  final int cogs;

  /// Current stock on hand (all-time, not period-scoped).
  final int stock;

  /// Net units sold in the most recent [ProductInsights.trendWindowDays].
  final int recentUnits;

  /// Net units sold in the equally long window immediately before that.
  final int priorUnits;

  /// Average units sold per day over [ProductInsights.spanDays].
  final double dailyUnits;

  const ProductStat({
    required this.product,
    required this.units,
    required this.revenue,
    required this.cogs,
    required this.stock,
    required this.recentUnits,
    required this.priorUnits,
    required this.dailyUnits,
  });

  /// Gross margin earned on what sold in the period.
  int get margin => revenue - cogs;

  /// Margin as a share of sales (0.28 = 28 paisa of every rupee sold).
  double get marginRatio => revenue > 0 ? margin / revenue : 0;

  /// [marginRatio] as whole percent, for display.
  int get marginPct => (marginRatio * 100).round();

  /// Money currently tied up in this product: max(0, stock) × buy price.
  int get stockValue => stock > 0 ? stock * product.buyPrice : 0;

  /// Change in units sold between the previous window and the recent one.
  int get trendDelta => recentUnits - priorUnits;

  /// Roughly how many days the current stock lasts at the measured rate, or
  /// null when there is no measurable demand (nothing sold in the period).
  /// Out of stock while still in demand reads as 0 days.
  double? get daysOfCover {
    if (dailyUnits <= 0) return null;
    return stock > 0 ? stock / dailyUnits : 0;
  }

  /// Any activity at all — used to decide whether insights are worth showing.
  bool get isIdle => units == 0 && stock == 0;
}

/// Ranked product insights for one [Period], built in a single pass over the
/// ledger (so a large ledger costs one scan, not one scan per product).
class ProductInsights {
  final Period period;

  /// One entry per live (non-archived) product.
  final List<ProductStat> stats;

  /// Length of the recent/previous windows compared by [InsightLens.trending].
  final int trendWindowDays;

  /// Days of trading the demand rate was averaged over (at least 1).
  final int spanDays;

  /// The last day measured — the period's end, or today for an all-time period.
  /// Held so every derived cut-off stays deterministic (no second clock read).
  final String windowEnd;

  /// Low-stock threshold from settings, used by [InsightLens.restock].
  final int lowStock;

  const ProductInsights({
    required this.period,
    required this.stats,
    required this.trendWindowDays,
    required this.spanDays,
    required this.windowEnd,
    required this.lowStock,
  });

  /// "Restock soon" means the shelf empties within this many days at the
  /// measured rate.
  static const int restockCoverDays = 14;

  /// A product already at/under the shop's own low-stock threshold gets a wider
  /// window — a low count is worth acting on a little earlier.
  static const int lowStockCoverDays = 28;

  /// How many days each trend window covers, per period. Short enough to react,
  /// long enough that one quiet day is not a trend.
  static int trendWindowFor(PeriodKind kind) => switch (kind) {
        PeriodKind.month => 14,
        PeriodKind.quarter => 30,
        PeriodKind.allTime => 30,
      };

  /// Derives every figure from [ledger] for [period]. [now] is the device-local
  /// clock — it fixes "today" for the trend windows and the demand rate, and is
  /// passed in so the results are deterministic and testable.
  static ProductInsights build(Ledger ledger, Period period, DateTime now) {
    final todayIso = Period.fmtDate(now);
    final trendWindow = trendWindowFor(period.kind);

    // The trend windows end with the period (never in the future).
    var windowEnd = period.to ?? todayIso;
    if (windowEnd.compareTo(todayIso) > 0) windowEnd = todayIso;
    final recentFrom = Period.shiftDays(windowEnd, -(trendWindow - 1));
    final priorTo = Period.shiftDays(recentFrom, -1);
    final priorFrom = Period.shiftDays(priorTo, -(trendWindow - 1));

    final units = <String, int>{};
    final revenue = <String, int>{};
    final cogs = <String, int>{};
    final stock = <String, int>{};
    final recent = <String, int>{};
    final prior = <String, int>{};

    /// Earliest date the shop actually sold anything — the demand rate is
    /// averaged from here, so a shop that opened mid-month is not judged
    /// against the days before it traded.
    String? firstSaleDate;

    void add(Map<String, int> m, String key, int delta) =>
        m[key] = (m[key] ?? 0) + delta;

    for (final t in ledger.txns) {
      switch (t.type) {
        case TxnType.stockin:
          final pid = t.productId;
          if (pid != null) add(stock, pid, t.qty ?? 0);
          break;

        case TxnType.sale:
        case TxnType.returnGoods:
          // A return is a sale with the sign flipped, at the snapshot prices
          // the goods left at.
          final sign = t.type == TxnType.sale ? 1 : -1;
          if (firstSaleDate == null || t.date.compareTo(firstSaleDate) < 0) {
            firstSaleDate = t.date;
          }
          final inPeriod = period.contains(t.date);
          final inRecent = t.date.compareTo(recentFrom) >= 0 &&
              t.date.compareTo(windowEnd) <= 0;
          final inPrior = !inRecent &&
              t.date.compareTo(priorFrom) >= 0 &&
              t.date.compareTo(priorTo) <= 0;

          for (final l in t.lines) {
            add(stock, l.productId, -sign * l.qty);
            if (inPeriod) {
              add(units, l.productId, sign * l.qty);
              add(revenue, l.productId, sign * l.lineSell);
              add(cogs, l.productId, sign * l.lineBuy);
            }
            if (inRecent) {
              add(recent, l.productId, sign * l.qty);
            } else if (inPrior) {
              add(prior, l.productId, sign * l.qty);
            }
          }
          break;

        default:
          break;
      }
    }

    // Days of trading inside the period: from the later of the period start and
    // the first sale, to the earlier of the period end and today.
    var spanStart = period.from ?? firstSaleDate ?? windowEnd;
    if (firstSaleDate != null && firstSaleDate.compareTo(spanStart) > 0) {
      spanStart = firstSaleDate;
    }
    final spanDays = _daysInclusive(spanStart, windowEnd);

    final stats = <ProductStat>[];
    for (final p in ledger.products) {
      if (p.archived) continue;
      final u = units[p.id] ?? 0;
      stats.add(ProductStat(
        product: p,
        units: u,
        revenue: revenue[p.id] ?? 0,
        cogs: cogs[p.id] ?? 0,
        stock: stock[p.id] ?? 0,
        recentUnits: recent[p.id] ?? 0,
        priorUnits: prior[p.id] ?? 0,
        // Returns can push net units negative; that is not demand.
        dailyUnits: u > 0 ? u / spanDays : 0,
      ));
    }

    return ProductInsights(
      period: period,
      stats: stats,
      trendWindowDays: trendWindow,
      spanDays: spanDays,
      windowEnd: windowEnd,
      lowStock: ledger.settings.lowStock,
    );
  }

  /// True when there is nothing to say yet (no stock, no sales).
  bool get isEmpty => stats.every((s) => s.isIdle);

  /// Products ranked for [lens], best (or most urgent) first. Products the lens
  /// has nothing to say about are left out entirely, so an empty list honestly
  /// means "nothing to report" rather than "the bottom of the catalog".
  List<ProductStat> ranked(InsightLens lens) {
    final out = switch (lens) {
      // Volume. Ties broken by revenue so the more valuable one leads.
      InsightLens.fastMovers => _pick(
          (s) => s.units > 0,
          (a, b) => _cmp(b.units, a.units, () => _cmp(b.revenue, a.revenue)),
        ),

      // Money in.
      InsightLens.bestSellers => _pick(
          (s) => s.revenue > 0,
          (a, b) => _cmp(b.revenue, a.revenue, () => _cmp(b.margin, a.margin)),
        ),

      // Money kept. Only products actually in profit belong here.
      InsightLens.topProfit => _pick(
          (s) => s.margin > 0,
          (a, b) => _cmp(b.margin, a.margin, () => _cmp(b.revenue, a.revenue)),
        ),

      // Margin quality, not size.
      InsightLens.bestMargin => _pick(
          (s) => s.revenue > 0 && s.marginRatio > 0,
          (a, b) => _cmpD(
              b.marginRatio, a.marginRatio, () => _cmp(b.margin, a.margin)),
        ),

      // Demand rising. Needs current sales, not just a quiet previous window.
      InsightLens.trending => _pick(
          (s) => s.recentUnits > 0 && s.trendDelta > 0,
          (a, b) => _cmp(
              b.trendDelta, a.trendDelta, () => _cmp(b.recentUnits, a.recentUnits)),
        ),

      // Urgency: least cover first. Only products with real demand.
      InsightLens.restock => _pick(
          _needsRestock,
          (a, b) => _cmpD(a.daysOfCover ?? 0, b.daysOfCover ?? 0,
              () => _cmp(b.units, a.units)),
        ),

      // Stock sitting still. Ties broken by money tied up.
      InsightLens.slowMovers => _pick(
          (s) => s.stock > 0 && !_isTooNewToJudge(s),
          (a, b) =>
              _cmp(a.units, b.units, () => _cmp(b.stockValue, a.stockValue)),
        ),

      // Thin or negative margin, biggest sellers first — those cost the most.
      InsightLens.thinMargin => _pick(
          (s) => s.revenue > 0,
          (a, b) => _cmpD(
              a.marginRatio, b.marginRatio, () => _cmp(b.revenue, a.revenue)),
        ),
    };
    return out;
  }

  /// The single most notable product for [lens], or null when the lens has
  /// nothing to report.
  ProductStat? top(InsightLens lens) {
    final list = ranked(lens);
    return list.isEmpty ? null : list.first;
  }

  /// The lenses shown as one-line headlines on Home: what sells, what earns,
  /// what to buy, what is picking up. Lenses with nothing to report are
  /// dropped, so the card never shows a filler row.
  static const List<InsightLens> homeLenses = [
    InsightLens.fastMovers,
    InsightLens.topProfit,
    InsightLens.restock,
    InsightLens.trending,
  ];

  /// [homeLenses] paired with one product each, empty lenses removed.
  ///
  /// A single product often tops several lenses at once (the fast mover is
  /// frequently also the one to reorder). Repeating it four times would waste
  /// the card, so each lens takes its highest-ranked product that another lens
  /// has not already claimed — four different products, four different things to
  /// notice. The full ranking, un-deduplicated, is on the insights screen.
  List<(InsightLens, ProductStat)> get headlines {
    final used = <String>{};
    final out = <(InsightLens, ProductStat)>[];
    for (final lens in homeLenses) {
      for (final s in ranked(lens)) {
        if (used.add(s.product.id)) {
          out.add((lens, s));
          break;
        }
      }
    }
    return out;
  }

  /// Restock candidates: still selling, and about to run out — within
  /// [restockCoverDays], or [lowStockCoverDays] if the count is already at or
  /// under the shop's low-stock threshold.
  ///
  /// Deliberately cover-based, not count-based. A product with three units left
  /// that sells one a month is not urgent, and Home's "Low stock · N items" chip
  /// already reports low counts on their own.
  bool _needsRestock(ProductStat s) {
    final cover = s.daysOfCover;
    if (cover == null) return false; // no demand → nothing to reorder for
    final limit = s.stock <= lowStock ? lowStockCoverDays : restockCoverDays;
    return cover <= limit;
  }

  /// A product added within the last trend window has not had a fair chance to
  /// sell, so it is never called slow.
  bool _isTooNewToJudge(ProductStat s) {
    final cutoff = Period.shiftDays(windowEnd, -trendWindowDays);
    final added = Period.fmtDate(
        DateTime.fromMillisecondsSinceEpoch(s.product.createdAt));
    return added.compareTo(cutoff) > 0;
  }

  List<ProductStat> _pick(bool Function(ProductStat) keep,
      int Function(ProductStat, ProductStat) order) {
    // `List.sort` is not stable, so every comparator ends on product identity.
    // Two products that tie on the metric then always rank the same way, and
    // the list never reshuffles between rebuilds.
    return stats.where(keep).toList()
      ..sort((a, b) {
        final c = order(a, b);
        return c != 0 ? c : _byIdentity(a, b);
      });
  }

  static int _byIdentity(ProductStat a, ProductStat b) {
    final n = a.product.name
        .toLowerCase()
        .compareTo(b.product.name.toLowerCase());
    if (n != 0) return n;
    final s = a.product.size.compareTo(b.product.size);
    return s != 0 ? s : a.product.id.compareTo(b.product.id);
  }

  /// Compare ints with an optional tiebreaker, keeping sorts total and stable.
  static int _cmp(int a, int b, [int Function()? then]) {
    final c = a.compareTo(b);
    if (c != 0 || then == null) return c;
    return then();
  }

  static int _cmpD(double a, double b, [int Function()? then]) {
    final c = a.compareTo(b);
    if (c != 0 || then == null) return c;
    return then();
  }

  /// Whole days from [fromIso] to [toIso], inclusive of both ends; at least 1.
  static int _daysInclusive(String fromIso, String toIso) {
    final n = Period.daysBetween(fromIso, toIso) + 1;
    return n < 1 ? 1 : n;
  }
}
