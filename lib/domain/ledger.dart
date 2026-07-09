/// The derivation engine (Section 6). Every balance, stock level, and total is
/// computed here by summing transactions — never stored as an editable number.
///
/// Pure Dart. These functions must reproduce Appendix A exactly. The production
/// app may compute equivalents with SQL aggregates, but they must return
/// identical results to these definitions.
library;

import 'models.dart';
import 'period.dart';

/// Profit recognised for a single payment, and the running totals after it.
class PaymentProfit {
  final String paymentId;
  final int profit;
  const PaymentProfit(this.paymentId, this.profit);
}

/// An immutable snapshot of the ledger used to derive all figures.
class Ledger {
  final List<Product> products;
  final List<Salesperson> salespersons;
  final List<Txn> txns;
  final StoreSettings settings;

  /// External customers (retailers). Default empty so pure-domain tests that
  /// only exercise the transaction ledger need not supply them.
  final List<Shop> shops;

  /// "Shop bought from us" events (amount + date, no credit/stock effect).
  final List<ShopPurchase> shopPurchases;

  Ledger({
    required this.products,
    required this.salespersons,
    required this.txns,
    required this.settings,
    this.shops = const [],
    this.shopPurchases = const [],
  });

  Product? product(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Salesperson? salesperson(String id) {
    for (final s in salespersons) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---- 6.1 Product stock ----------------------------------------------------

  /// stock(P) = Σ stockin.qty + Σ return line.qty − Σ sale line.qty
  int stock(String productId) {
    var n = 0;
    for (final t in txns) {
      switch (t.type) {
        case TxnType.stockin:
          if (t.productId == productId) n += t.qty ?? 0;
          break;
        case TxnType.sale:
          for (final l in t.lines) {
            if (l.productId == productId) n -= l.qty;
          }
          break;
        case TxnType.returnGoods:
          for (final l in t.lines) {
            if (l.productId == productId) n += l.qty;
          }
          break;
        default:
          break;
      }
    }
    return n;
  }

  /// Net units of a product sold to salespersons: Σ sale line qty − Σ return
  /// line qty. (What has left the shop for good, at the line level.)
  int unitsSold(String productId) {
    var n = 0;
    for (final t in txns) {
      if (t.type == TxnType.sale) {
        for (final l in t.lines) {
          if (l.productId == productId) n += l.qty;
        }
      } else if (t.type == TxnType.returnGoods) {
        for (final l in t.lines) {
          if (l.productId == productId) n -= l.qty;
        }
      }
    }
    return n;
  }

  /// Net sell-value of a product across all sales, less returns (using the
  /// unit_sell snapshots). The revenue this product has generated.
  int salesRevenue(String productId) {
    var n = 0;
    for (final t in txns) {
      if (t.type == TxnType.sale) {
        for (final l in t.lines) {
          if (l.productId == productId) n += l.lineSell;
        }
      } else if (t.type == TxnType.returnGoods) {
        for (final l in t.lines) {
          if (l.productId == productId) n -= l.lineSell;
        }
      }
    }
    return n;
  }

  /// Net cost basis (unit_buy snapshots) of a product's units sold, less
  /// returns. The cost of goods actually sold for this product.
  int productCogs(String productId) {
    var n = 0;
    for (final t in txns) {
      if (t.type == TxnType.sale) {
        for (final l in t.lines) {
          if (l.productId == productId) n += l.lineBuy;
        }
      } else if (t.type == TxnType.returnGoods) {
        for (final l in t.lines) {
          if (l.productId == productId) n -= l.lineBuy;
        }
      }
    }
    return n;
  }

  /// Gross margin realised on a product's net units sold, using the price
  /// snapshots: salesRevenue − productCogs. (Not cash-basis profit — that is
  /// recognised per salesperson in 6.5 — but a true per-product margin.)
  int productGrossMargin(String productId) =>
      salesRevenue(productId) - productCogs(productId);

  /// Value currently sitting as stock for one product: max(0, stock) × buy.
  int productStockValue(String productId) {
    final p = product(productId);
    if (p == null) return 0;
    final s = stock(productId);
    return s > 0 ? s * p.buyPrice : 0;
  }

  /// Every ledger movement that touches [productId] — stock-ins for it, plus
  /// sales/returns whose lines include it — oldest first (by date, createdAt).
  List<Txn> productMovements(String productId) {
    final out = <Txn>[];
    for (final t in txns) {
      switch (t.type) {
        case TxnType.stockin:
          if (t.productId == productId) out.add(t);
          break;
        case TxnType.sale:
        case TxnType.returnGoods:
          if (t.lines.any((l) => l.productId == productId)) out.add(t);
          break;
        default:
          break;
      }
    }
    out.sort(Txn.compare);
    return out;
  }

  // ---- 6.2 Goods taken (sell value & cost basis) ----------------------------

  /// sellTaken(S) = Σ saleLineSell − Σ returnLineSell (unit_sell snapshots)
  int sellTaken(String salespersonId) {
    var n = 0;
    for (final t in txns) {
      if (t.salespersonId != salespersonId) continue;
      if (t.type == TxnType.sale) n += t.linesSell;
      if (t.type == TxnType.returnGoods) n -= t.linesSell;
    }
    return n;
  }

  /// costTaken(S) = Σ saleLineBuy − Σ returnLineBuy (unit_buy snapshots)
  int costTaken(String salespersonId) {
    var n = 0;
    for (final t in txns) {
      if (t.salespersonId != salespersonId) continue;
      if (t.type == TxnType.sale) n += t.linesBuy;
      if (t.type == TxnType.returnGoods) n -= t.linesBuy;
    }
    return n;
  }

  // ---- 6.3 Salesperson balance ---------------------------------------------

  int paymentsBy(String salespersonId) {
    var n = 0;
    for (final t in txns) {
      if (t.type == TxnType.payment && t.salespersonId == salespersonId) {
        n += t.amount ?? 0;
      }
    }
    return n;
  }

  /// balance(S) = opening + sellTaken − Σ payment.amount
  int balance(String salespersonId) {
    final s = salesperson(salespersonId);
    final opening = s?.opening ?? 0;
    return opening + sellTaken(salespersonId) - paymentsBy(salespersonId);
  }

  /// Balance from all of a salesperson's transactions strictly before [before]
  /// (by date, then createdAt). Used for "previous balance" on receipts.
  int balanceBefore(String salespersonId, Txn before) {
    final s = salesperson(salespersonId);
    var bal = s?.opening ?? 0;
    for (final t in txns) {
      if (t.salespersonId != salespersonId) continue;
      if (Txn.compare(t, before) >= 0) continue; // strictly before
      switch (t.type) {
        case TxnType.sale:
          bal += t.linesSell;
          break;
        case TxnType.returnGoods:
          bal -= t.linesSell;
          break;
        case TxnType.payment:
          bal -= t.amount ?? 0;
          break;
        default:
          break;
      }
    }
    return bal;
  }

  // ---- 6.4 Store-wide money -------------------------------------------------

  int get totalPayments =>
      txns.where((t) => t.type == TxnType.payment).fold(0, (s, t) => s + (t.amount ?? 0));

  int get totalStockInCost => txns
      .where((t) => t.type == TxnType.stockin)
      .fold(0, (s, t) => s + (t.qty ?? 0) * (t.unitBuy ?? 0));

  int get totalExpenses =>
      txns.where((t) => t.type == TxnType.expense).fold(0, (s, t) => s + (t.amount ?? 0));

  /// cashOnHand = openingCash + Σ payments − Σ stockin cost − Σ expenses
  int get cashOnHand =>
      settings.openingCash + totalPayments - totalStockInCost - totalExpenses;

  /// stockValue = Σ max(0, stock(P)) × buyPrice(P)
  int get stockValue {
    var n = 0;
    for (final p in products) {
      final s = stock(p.id);
      if (s > 0) n += s * p.buyPrice;
    }
    return n;
  }

  /// totalOwed = Σ balance(S)
  int get totalOwed =>
      salespersons.fold(0, (sum, s) => sum + balance(s.id));

  // ---- 6.5 Profit — cash-basis, proportional -------------------------------

  /// Per-payment recognised profit for one salesperson, walking their events
  /// in chronological order (date, then createdAt).
  List<PaymentProfit> paymentProfits(String salespersonId) {
    final s = salesperson(salespersonId);
    final opening = s?.opening ?? 0;
    final marginBp = s?.openingMarginBp ?? 0;

    final events = txns
        .where((t) =>
            t.salespersonId == salespersonId &&
            (t.type == TxnType.sale ||
                t.type == TxnType.returnGoods ||
                t.type == TxnType.payment))
        .toList()
      ..sort(Txn.compare);

    var cumSell = opening;
    // opening defaults to 0 margin → cumCost = cumSell
    var cumCost = opening - (opening * marginBp) ~/ 10000;
    var recognised = 0;
    final out = <PaymentProfit>[];

    for (final e in events) {
      switch (e.type) {
        case TxnType.sale:
          cumSell += e.linesSell;
          cumCost += e.linesBuy;
          break;
        case TxnType.returnGoods:
          cumSell -= e.linesSell;
          cumCost -= e.linesBuy;
          break;
        case TxnType.payment:
          final a = e.amount ?? 0;
          final marginPool = (cumSell - cumCost) - recognised;
          final ratio = cumSell > 0 ? (cumSell - cumCost) / cumSell : 0.0;
          var p = (a * ratio).round();
          final cap = marginPool > 0 ? marginPool : 0;
          if (p < 0) p = 0;
          if (p > cap) p = cap;
          recognised += p;
          out.add(PaymentProfit(e.id, p));
          break;
        default:
          break;
      }
    }
    return out;
  }

  /// Total profit recognised for a salesperson across all their payments.
  int recognisedProfit(String salespersonId) =>
      paymentProfits(salespersonId).fold(0, (s, p) => s + p.profit);

  /// Gross recognised profit (all salespersons) for payments dated in [period].
  int recognisedProfitInPeriod(Period period) {
    final byId = {for (final t in txns) t.id: t};
    var total = 0;
    for (final s in salespersons) {
      for (final pp in paymentProfits(s.id)) {
        final t = byId[pp.paymentId];
        if (t != null && period.contains(t.date)) total += pp.profit;
      }
    }
    return total;
  }

  int expensesInPeriod(Period period) => txns
      .where((t) => t.type == TxnType.expense && period.contains(t.date))
      .fold(0, (s, t) => s + (t.amount ?? 0));

  /// profit(period) = Σ per-payment profit in period − Σ expenses in period
  int netProfitInPeriod(Period period) =>
      recognisedProfitInPeriod(period) - expensesInPeriod(period);

  // ---- 6.7 Rankings and alerts ---------------------------------------------

  /// takenInPeriod(S) = Σ saleLineSell − Σ returnLineSell for txns in period.
  int takenInPeriod(String salespersonId, Period period) {
    var n = 0;
    for (final t in txns) {
      if (t.salespersonId != salespersonId) continue;
      if (!period.contains(t.date)) continue;
      if (t.type == TxnType.sale) n += t.linesSell;
      if (t.type == TxnType.returnGoods) n -= t.linesSell;
    }
    return n;
  }

  /// Salespersons sorted by goods taken in period, descending, excluding zero.
  List<MapEntry<Salesperson, int>> topSalespersons(Period period) {
    final ranked = salespersons
        .map((s) => MapEntry(s, takenInPeriod(s.id, period)))
        .where((e) => e.value != 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked;
  }

  /// Products where stock(P) <= lowStock threshold.
  List<Product> lowStockProducts() {
    final threshold = settings.lowStock;
    return products
        .where((p) => !p.archived && stock(p.id) <= threshold)
        .toList();
  }

  /// Recurring expenses (Section 9.5) that still need posting for [thisMonth]:
  /// each category that has ever been tagged recurring, with its most recent
  /// amount, excluding categories already posted in the current month.
  /// Never posts anything — just suggests, for the month-start confirm sheet.
  List<({String category, int amount})> recurringExpenseTemplates(
      Period thisMonth) {
    final recurring = txns
        .where((t) => t.type == TxnType.expense && t.recurring)
        .toList()
      ..sort(Txn.compare);

    // Most recent amount per recurring category.
    final latest = <String, int>{};
    for (final t in recurring) {
      final cat = (t.category ?? '').trim();
      if (cat.isEmpty) continue;
      latest[cat] = t.amount ?? 0; // later entries overwrite (sorted asc)
    }

    // Categories already having any expense this month — don't duplicate.
    final postedThisMonth = txns
        .where((t) =>
            t.type == TxnType.expense && thisMonth.contains(t.date))
        .map((t) => (t.category ?? '').trim())
        .toSet();

    return [
      for (final e in latest.entries)
        if (!postedThisMonth.contains(e.key))
          (category: e.key, amount: e.value),
    ];
  }

  // ---- Shops (external customers) ------------------------------------------
  //
  // Shops are retailers who buy goods to resell. Unlike salespersons they are
  // not tracked on credit — the app records how much each shop buys so the
  // owner can see who buys most, who is new, and who is a reliable long-term
  // customer. All figures below are derived from [shopPurchases].

  /// Heuristic thresholds for [shopSegment]. Centralised so they are easy to
  /// tune. Days are measured against the reference "now" passed by the caller.
  static const int newWindowDays = 30; // still "new" within a month of joining
  static const int inactiveDays = 90; // no purchase in this long → inactive
  static const int loyalTenureDays = 90; // must have been a customer this long
  static const int loyalCountMin = 5; // …and bought at least this many times
  static const int loyalRecencyDays = 45; // …with a purchase this recent

  Shop? shop(String id) {
    for (final s in shops) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// A shop's purchases, oldest first.
  List<ShopPurchase> purchasesOf(String shopId) {
    final list =
        shopPurchases.where((p) => p.shopId == shopId).toList()
          ..sort(ShopPurchase.compare);
    return list;
  }

  /// Total value a shop has ever bought.
  int totalBought(String shopId) => shopPurchases
      .where((p) => p.shopId == shopId)
      .fold(0, (s, p) => s + p.amount);

  /// Value a shop bought within [period].
  int boughtInPeriod(String shopId, Period period) => shopPurchases
      .where((p) => p.shopId == shopId && period.contains(p.date))
      .fold(0, (s, p) => s + p.amount);

  /// How many separate purchases a shop has made.
  int purchaseCount(String shopId) =>
      shopPurchases.where((p) => p.shopId == shopId).length;

  /// Date of a shop's first purchase, or null if it has never bought.
  String? firstPurchaseDate(String shopId) {
    final list = purchasesOf(shopId);
    return list.isEmpty ? null : list.first.date;
  }

  /// Date of a shop's most recent purchase, or null if it has never bought.
  String? lastPurchaseDate(String shopId) {
    final list = purchasesOf(shopId);
    return list.isEmpty ? null : list.last.date;
  }

  /// Classify a shop from its buying behaviour, relative to [now] (device-local
  /// clock). Pure function of the ledger — never stored.
  ShopSegment shopSegment(String shopId, DateTime now) {
    final purchases = purchasesOf(shopId);
    final joined = shop(shopId)?.createdAt;

    // Tenure: days since the relationship began (earliest of "added" and first
    // purchase), so a back-dated first sale still counts as long tenure.
    var startMs = joined ?? now.millisecondsSinceEpoch;
    final firstDate = purchases.isEmpty ? null : _parseDate(purchases.first.date);
    if (firstDate != null && firstDate.millisecondsSinceEpoch < startMs) {
      startMs = firstDate.millisecondsSinceEpoch;
    }
    final tenureDays = _daysBetween(startMs, now);

    if (purchases.isEmpty) {
      // Added but never bought: new for a while, then treated as inactive.
      return tenureDays <= newWindowDays
          ? ShopSegment.fresh
          : ShopSegment.inactive;
    }

    final lastDate = _parseDate(purchases.last.date);
    final recencyDays =
        lastDate == null ? 0 : _daysBetween(lastDate.millisecondsSinceEpoch, now);
    final count = purchases.length;

    if (recencyDays > inactiveDays) return ShopSegment.inactive;
    if (tenureDays <= newWindowDays || count <= 1) return ShopSegment.fresh;
    if (tenureDays >= loyalTenureDays &&
        count >= loyalCountMin &&
        recencyDays <= loyalRecencyDays) {
      return ShopSegment.reliable;
    }
    return ShopSegment.regular;
  }

  /// Shops ranked by how much they bought in [period], descending, excluding
  /// those with zero. Answers "who buys more".
  List<MapEntry<Shop, int>> topShops(Period period) {
    final ranked = shops
        .where((s) => !s.archived)
        .map((s) => MapEntry(s, boughtInPeriod(s.id, period)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked;
  }

  /// The highest all-time buying value across non-archived shops (0 if none
  /// have bought). Used to flag the top buyer(s) with a badge.
  int get topBoughtValue {
    var max = 0;
    for (final s in shops) {
      if (s.archived) continue;
      final t = totalBought(s.id);
      if (t > max) max = t;
    }
    return max;
  }

  /// Whole-days from an epoch-ms instant to [now], measured on calendar dates
  /// (ignores time-of-day) so "today" is 0 and yesterday is 1.
  static int _daysBetween(int fromMs, DateTime now) {
    final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays;
  }

  static DateTime? _parseDate(String iso) => DateTime.tryParse(iso);
}
