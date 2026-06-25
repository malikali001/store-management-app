/// Domain entities. Pure Dart — no Flutter, no database imports.
///
/// All money is an integer in the smallest unit the shop uses (minor units).
/// Never use floating point for stored amounts; round only at display.
library;

/// The five movements recorded in the append-only ledger.
enum TxnType {
  stockin,
  sale,
  returnGoods,
  payment,
  expense;

  /// Wire/storage value used in the database and backups.
  String get wire => switch (this) {
        TxnType.stockin => 'stockin',
        TxnType.sale => 'sale',
        TxnType.returnGoods => 'return',
        TxnType.payment => 'payment',
        TxnType.expense => 'expense',
      };

  static TxnType fromWire(String v) => switch (v) {
        'stockin' => TxnType.stockin,
        'sale' => TxnType.sale,
        'return' => TxnType.returnGoods,
        'payment' => TxnType.payment,
        'expense' => TxnType.expense,
        _ => throw ArgumentError('Unknown transaction type: $v'),
      };
}

class Product {
  final String id;
  final String code;
  final String name;
  final String brand;
  final String category;
  final String size; // empty string when item has no size
  final int buyPrice; // minor units
  final int sellPrice; // minor units
  final bool archived;
  final int createdAt; // epoch ms

  const Product({
    required this.id,
    this.code = '',
    required this.name,
    this.brand = '',
    this.category = '',
    this.size = '',
    required this.buyPrice,
    required this.sellPrice,
    this.archived = false,
    required this.createdAt,
  });

  Product copyWith({
    String? code,
    String? name,
    String? brand,
    String? category,
    String? size,
    int? buyPrice,
    int? sellPrice,
    bool? archived,
  }) =>
      Product(
        id: id,
        code: code ?? this.code,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        category: category ?? this.category,
        size: size ?? this.size,
        buyPrice: buyPrice ?? this.buyPrice,
        sellPrice: sellPrice ?? this.sellPrice,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

class Salesperson {
  final String id;
  final String name;
  final String phone;
  final int opening; // amount already owed at start, minor units
  final int openingMarginBp; // margin on opening balance, basis points
  final bool archived;
  final int createdAt;

  const Salesperson({
    required this.id,
    required this.name,
    this.phone = '',
    this.opening = 0,
    this.openingMarginBp = 0,
    this.archived = false,
    required this.createdAt,
  });

  Salesperson copyWith({
    String? name,
    String? phone,
    int? opening,
    int? openingMarginBp,
    bool? archived,
  }) =>
      Salesperson(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        opening: opening ?? this.opening,
        openingMarginBp: openingMarginBp ?? this.openingMarginBp,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

/// One sale/return line item. Prices are snapshots taken at the moment of
/// the transaction so editing a product later never changes history.
class TxnLine {
  final String id;
  final String transactionId;
  final String productId;
  final int qty;
  final int unitSell; // snapshot
  final int unitBuy; // snapshot (cost basis for profit)

  const TxnLine({
    required this.id,
    required this.transactionId,
    required this.productId,
    required this.qty,
    required this.unitSell,
    required this.unitBuy,
  });

  int get lineSell => qty * unitSell;
  int get lineBuy => qty * unitBuy;
}

/// One ledger row. Lines (for sale/return) are attached separately.
class Txn {
  final String id;
  final TxnType type;
  final String date; // 'YYYY-MM-DD', local date
  final int createdAt; // epoch ms, tiebreaker for same-date ordering
  final String? salespersonId; // sale | return | payment
  final String? productId; // stockin only
  final int? qty; // stockin only
  final int? unitBuy; // stockin: buy price snapshot
  final int? amount; // payment | expense
  final String? category; // expense
  final bool recurring; // expense: tagged monthly
  final String? note;
  final List<TxnLine> lines; // sale | return

  const Txn({
    required this.id,
    required this.type,
    required this.date,
    required this.createdAt,
    this.salespersonId,
    this.productId,
    this.qty,
    this.unitBuy,
    this.amount,
    this.category,
    this.recurring = false,
    this.note,
    this.lines = const [],
  });

  /// Total sell value of this transaction's lines (sale/return).
  int get linesSell => lines.fold(0, (s, l) => s + l.lineSell);

  /// Total cost (buy) value of this transaction's lines.
  int get linesBuy => lines.fold(0, (s, l) => s + l.lineBuy);

  /// Stable chronological comparator: by date, then createdAt.
  static int compare(Txn a, Txn b) {
    final d = a.date.compareTo(b.date);
    if (d != 0) return d;
    return a.createdAt.compareTo(b.createdAt);
  }
}

/// App settings, already parsed into typed values.
class StoreSettings {
  final String storeName;
  final String currency;
  final int decimalPlaces;
  final int openingCash; // minor units
  final int lowStock;

  const StoreSettings({
    this.storeName = 'My Store',
    this.currency = '',
    this.decimalPlaces = 0,
    this.openingCash = 0,
    this.lowStock = 20,
  });
}
