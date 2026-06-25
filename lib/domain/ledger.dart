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

  Ledger({
    required this.products,
    required this.salespersons,
    required this.txns,
    required this.settings,
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
}
