import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/ledger.dart';
import '../domain/sample_data.dart';
import '../domain/demo_data.dart';
import 'database.dart' as db;

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Thrown when an operation is blocked by a business rule (Section 9).
class DomainError implements Exception {
  final String message;
  DomainError(this.message);
  @override
  String toString() => message;
}

/// Maps the Drift database to the domain layer and exposes a reactive [Ledger].
/// All writes are single DB transactions; all reads are derived from the ledger.
class StoreRepository {
  final db.AppDatabase _db;
  StoreRepository(this._db);

  // ---- Reactive ledger ------------------------------------------------------

  /// Emits a fresh [Ledger] snapshot whenever any underlying table changes.
  Stream<Ledger> watchLedger() {
    final controller = StreamController<Ledger>();
    StreamSubscription? sub;
    // Re-derive the full ledger on every table change (any insert/delete/update
    // anywhere invalidates the derived totals).
    Future<void> reload() async {
      try {
        controller.add(await loadLedger());
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    sub = _db.tableUpdates().listen((_) => reload());
    controller.onListen = reload;
    controller.onCancel = () => sub?.cancel();
    return controller.stream;
  }

  Future<Ledger> loadLedger() async {
    final results = await Future.wait([
      _db.select(_db.products).get(),
      _db.select(_db.salespersons).get(),
      _db.select(_db.transactions).get(),
      _db.select(_db.transactionLines).get(),
      _db.select(_db.settingsItems).get(),
    ]);
    final pRows = results[0] as List<db.Product>;
    final sRows = results[1] as List<db.Salesperson>;
    final tRows = results[2] as List<db.Transaction>;
    final lRows = results[3] as List<db.TransactionLine>;
    final setRows = results[4] as List<db.SettingsItem>;

    final linesByTxn = <String, List<TxnLine>>{};
    for (final l in lRows) {
      (linesByTxn[l.transactionId] ??= []).add(TxnLine(
        id: l.id,
        transactionId: l.transactionId,
        productId: l.productId,
        qty: l.qty,
        unitSell: l.unitSell,
        unitBuy: l.unitBuy,
      ));
    }

    return Ledger(
      products: pRows.map(_toProduct).toList(),
      salespersons: sRows.map(_toSalesperson).toList(),
      txns: tRows.map((t) => _toTxn(t, linesByTxn[t.id] ?? const [])).toList(),
      settings: _settingsFrom(setRows),
    );
  }

  // ---- Mappers --------------------------------------------------------------

  Product _toProduct(db.Product r) => Product(
        id: r.id,
        code: r.code,
        name: r.name,
        brand: r.brand,
        category: r.category,
        size: r.size,
        buyPrice: r.buyPrice,
        sellPrice: r.sellPrice,
        archived: r.archived,
        createdAt: r.createdAt,
      );

  Salesperson _toSalesperson(db.Salesperson r) => Salesperson(
        id: r.id,
        name: r.name,
        phone: r.phone,
        opening: r.opening,
        openingMarginBp: r.openingMarginBp,
        archived: r.archived,
        createdAt: r.createdAt,
      );

  Txn _toTxn(db.Transaction r, List<TxnLine> lines) => Txn(
        id: r.id,
        type: TxnType.fromWire(r.type),
        date: r.date,
        createdAt: r.createdAt,
        salespersonId: r.salespersonId,
        productId: r.productId,
        qty: r.qty,
        unitBuy: r.unitBuy,
        amount: r.amount,
        category: r.category,
        recurring: r.recurring,
        note: r.note,
        lines: lines,
      );

  StoreSettings _settingsFrom(List<db.SettingsItem> rows) {
    final m = {for (final r in rows) r.key: r.value};
    return StoreSettings(
      storeName: m['store_name'] ?? 'My Store',
      currency: m['currency'] ?? '',
      decimalPlaces: int.tryParse(m['decimal_places'] ?? '') ?? 0,
      openingCash: int.tryParse(m['opening_cash'] ?? '') ?? 0,
      lowStock: int.tryParse(m['low_stock'] ?? '') ?? 20,
    );
  }

  // ---- Settings & lists -----------------------------------------------------

  Future<void> setSetting(String key, String value) =>
      _db.into(_db.settingsItems).insertOnConflictUpdate(
          db.SettingsItemsCompanion.insert(key: key, value: value));

  Future<String?> rawSetting(String key) async {
    final row = await (_db.select(_db.settingsItems)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<List<String>> listValues(String kind) async {
    final rows = await (_db.select(_db.lists)
          ..where((t) => t.kind.equals(kind)))
        .get();
    final v = rows.map((r) => r.value).toList()..sort();
    return v;
  }

  Future<void> addListValue(String kind, String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    await _db.into(_db.lists).insertOnConflictUpdate(
        db.ListsCompanion.insert(kind: kind, value: v));
  }

  Future<void> removeListValue(String kind, String value) =>
      (_db.delete(_db.lists)
            ..where((t) => t.kind.equals(kind) & t.value.equals(value)))
          .go();

  /// Records brand/category/size typed on a product into their lists.
  Future<void> _captureProductLists(Product p) async {
    if (p.brand.isNotEmpty) await addListValue('brand', p.brand);
    if (p.category.isNotEmpty) await addListValue('category', p.category);
    if (p.size.isNotEmpty) await addListValue('size', p.size);
  }

  // ---- Products -------------------------------------------------------------

  Future<bool> codeExists(String code, {String? exceptId}) async {
    if (code.trim().isEmpty) return false;
    final rows = await (_db.select(_db.products)
          ..where((t) => t.code.equals(code.trim())))
        .get();
    return rows.any((r) => r.id != exceptId);
  }

  Future<void> upsertProduct(Product p) async {
    await _db.transaction(() async {
      await _db.into(_db.products).insertOnConflictUpdate(db.ProductsCompanion.insert(
            id: p.id,
            code: Value(p.code),
            name: p.name,
            brand: Value(p.brand),
            category: Value(p.category),
            size: Value(p.size),
            buyPrice: p.buyPrice,
            sellPrice: p.sellPrice,
            archived: Value(p.archived),
            createdAt: p.createdAt,
          ));
      await _captureProductLists(p);
    });
  }

  Future<bool> productHasHistory(String productId) async {
    final asStockin = await (_db.select(_db.transactions)
          ..where((t) => t.productId.equals(productId)))
        .get();
    if (asStockin.isNotEmpty) return true;
    final asLine = await (_db.select(_db.transactionLines)
          ..where((t) => t.productId.equals(productId)))
        .get();
    return asLine.isNotEmpty;
  }

  /// Delete a product. Blocked if it appears in any transaction (Section 9.2).
  Future<void> deleteProduct(String productId) async {
    if (await productHasHistory(productId)) {
      throw DomainError(
          'This product appears in transactions and cannot be deleted. Archive it instead.');
    }
    await (_db.delete(_db.products)..where((t) => t.id.equals(productId))).go();
  }

  Future<void> archiveProduct(String productId, {bool archived = true}) =>
      (_db.update(_db.products)..where((t) => t.id.equals(productId)))
          .write(db.ProductsCompanion(archived: Value(archived)));

  // ---- Salespersons ---------------------------------------------------------

  Future<void> upsertSalesperson(Salesperson s) =>
      _db.into(_db.salespersons).insertOnConflictUpdate(
            db.SalespersonsCompanion.insert(
              id: s.id,
              name: s.name,
              phone: Value(s.phone),
              opening: Value(s.opening),
              openingMarginBp: Value(s.openingMarginBp),
              archived: Value(s.archived),
              createdAt: s.createdAt,
            ),
          );

  /// Remove a salesperson — allowed only when balance ≈ 0 (Section 9.3).
  Future<void> deleteSalesperson(String id) async {
    final ledger = await loadLedger();
    if (ledger.balance(id).abs() > 0) {
      throw DomainError(
          'This salesperson still has an outstanding balance. Settle it before removing.');
    }
    await (_db.delete(_db.salespersons)..where((t) => t.id.equals(id))).go();
  }

  // ---- Transactions ---------------------------------------------------------

  Future<void> _insertTxn(db.TransactionsCompanion t,
      {List<db.TransactionLinesCompanion> lines = const []}) async {
    await _db.transaction(() async {
      await _db.into(_db.transactions).insert(t);
      for (final l in lines) {
        await _db.into(_db.transactionLines).insert(l);
      }
    });
  }

  Future<void> deleteTransaction(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.transactionLines)
            ..where((t) => t.transactionId.equals(id)))
          .go();
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<String> addStockIn({
    required String productId,
    required int qty,
    required int unitBuy,
    required String date,
    String? note,
  }) async {
    final id = newId();
    await _insertTxn(db.TransactionsCompanion.insert(
      id: id,
      type: 'stockin',
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      productId: Value(productId),
      qty: Value(qty),
      unitBuy: Value(unitBuy),
      note: Value(note),
    ));
    return id;
  }

  /// Edit a stock-in entry as an atomic delete+create (Section 8) so every
  /// derived figure re-reconciles. The id and original [createdAt] are kept so
  /// the entry holds its chronological position.
  Future<void> editStockIn({
    required String id,
    required String productId,
    required int qty,
    required int unitBuy,
    required String date,
    String? note,
  }) async {
    await _db.transaction(() async {
      final old = await (_db.select(_db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      final createdAt = old?.createdAt ?? DateTime.now().millisecondsSinceEpoch;
      await (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
      await _db.into(_db.transactions).insert(db.TransactionsCompanion.insert(
            id: id,
            type: 'stockin',
            date: date,
            createdAt: createdAt,
            productId: Value(productId),
            qty: Value(qty),
            unitBuy: Value(unitBuy),
            note: Value(note),
          ));
    });
  }

  /// A single line for a sale/return: (productId, qty, unitSell, unitBuy).
  Future<String> addSaleOrReturn({
    required TxnType type, // sale | returnGoods
    required String salespersonId,
    required String date,
    required List<({String productId, int qty, int unitSell, int unitBuy})> lines,
    String? note,
  }) async {
    final id = newId();
    await _insertTxn(
      db.TransactionsCompanion.insert(
        id: id,
        type: type.wire,
        date: date,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        salespersonId: Value(salespersonId),
        note: Value(note),
      ),
      lines: [
        for (final l in lines)
          db.TransactionLinesCompanion.insert(
            id: newId(),
            transactionId: id,
            productId: l.productId,
            qty: l.qty,
            unitSell: l.unitSell,
            unitBuy: l.unitBuy,
          ),
      ],
    );
    return id;
  }

  Future<String> addPayment({
    required String salespersonId,
    required int amount,
    required String date,
    String? note,
  }) async {
    final id = newId();
    await _insertTxn(db.TransactionsCompanion.insert(
      id: id,
      type: 'payment',
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      salespersonId: Value(salespersonId),
      amount: Value(amount),
      note: Value(note),
    ));
    return id;
  }

  Future<String> addExpense({
    required String category,
    required int amount,
    required String date,
    bool recurring = false,
    String? note,
  }) async {
    final id = newId();
    await _insertTxn(db.TransactionsCompanion.insert(
      id: id,
      type: 'expense',
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      category: Value(category),
      amount: Value(amount),
      recurring: Value(recurring),
      note: Value(note),
    ));
    if (category.trim().isNotEmpty) {
      await addListValue('expense_category', category);
    }
    return id;
  }

  // ---- Seeding & reset ------------------------------------------------------

  Future<bool> isEmpty() async {
    final p = await _db.select(_db.products).get();
    return p.isEmpty;
  }

  /// On a fresh install the store starts EMPTY — the owner enters their own
  /// products and people. We only ensure sensible default settings exist so the
  /// app is usable (demo data is available on demand from Settings).
  Future<void> seedIfEmpty() async {
    final hasSettings =
        (await _db.select(_db.settingsItems).get()).isNotEmpty;
    if (hasSettings) return;
    await _writeSettings(const StoreSettings(
      storeName: 'My Store',
      currency: 'Rs ', // Pakistani Rupees
      decimalPlaces: 0,
      openingCash: 0,
      lowStock: 20,
    ));
  }

  /// Loads the realistic demo dataset (Crest Street Supplies), replacing all
  /// current data.
  Future<void> seedDemoData() async {
    final now = DateTime.now();
    final created = now.millisecondsSinceEpoch;
    final demo = DemoData.build(now, createdBase: created);
    await _db.transaction(() async {
      await _wipe();
      await _insertProducts(demo.products);
      await _insertSalespersons(demo.salespersons);
      await _insertTxns(demo.txns);
      await _insertList('brand', demo.brands);
      await _insertList('category', demo.categories);
      await _insertList('size', demo.sizes);
      await _insertList('expense_category', demo.expenseCategories);
      await _writeSettings(DemoData.settings);
    });
  }

  /// Clears everything and leaves an empty store (a fresh production start).
  /// Keeps the current settings (store name, currency, ...).
  Future<void> clearAllData() async {
    final keep = (await loadLedger()).settings;
    await _db.transaction(() async {
      await _wipe();
      await _writeSettings(keep);
    });
  }

  /// Replaces all data with the small Appendix A fixture. Used by tests and as
  /// a known-good reset.
  Future<void> resetToSampleData() async {
    final now = DateTime.now();
    final today = _fmtDate(now);
    final created = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _wipe();
      await _insertProducts(SampleData.products(created));
      await _insertSalespersons(SampleData.salespersons(created));
      await _insertTxns(SampleData.transactions(today, created));
      await _insertList('brand', {'Acme', 'Nova'});
      await _insertList('category', {'T-shirts', 'Footwear', 'Caps'});
      await _insertList('size', {'M', 'L', 'XL', '7', '8', 'Std'});
      await _insertList('expense_category', {'Rent', 'Transport', 'Labour'});
      await _writeSettings(SampleData.settings);
    });
  }

  Future<void> _insertProducts(List<Product> products) async {
    for (final p in products) {
      await _db.into(_db.products).insert(db.ProductsCompanion.insert(
            id: p.id,
            code: Value(p.code),
            name: p.name,
            brand: Value(p.brand),
            category: Value(p.category),
            size: Value(p.size),
            buyPrice: p.buyPrice,
            sellPrice: p.sellPrice,
            archived: Value(p.archived),
            createdAt: p.createdAt,
          ));
    }
  }

  Future<void> _insertSalespersons(List<Salesperson> people) async {
    for (final s in people) {
      await _db.into(_db.salespersons).insert(db.SalespersonsCompanion.insert(
            id: s.id,
            name: s.name,
            phone: Value(s.phone),
            opening: Value(s.opening),
            openingMarginBp: Value(s.openingMarginBp),
            createdAt: s.createdAt,
          ));
    }
  }

  Future<void> _insertTxns(List<Txn> txns) async {
    for (final t in txns) {
      await _db.into(_db.transactions).insert(db.TransactionsCompanion.insert(
            id: t.id,
            type: t.type.wire,
            date: t.date,
            createdAt: t.createdAt,
            salespersonId: Value(t.salespersonId),
            productId: Value(t.productId),
            qty: Value(t.qty),
            unitBuy: Value(t.unitBuy),
            amount: Value(t.amount),
            category: Value(t.category),
            recurring: Value(t.recurring),
            note: Value(t.note),
          ));
      for (final l in t.lines) {
        await _db.into(_db.transactionLines).insert(
            db.TransactionLinesCompanion.insert(
                id: l.id,
                transactionId: l.transactionId,
                productId: l.productId,
                qty: l.qty,
                unitSell: l.unitSell,
                unitBuy: l.unitBuy));
      }
    }
  }

  Future<void> _insertList(String kind, Set<String> values) async {
    for (final v in values) {
      await _db.into(_db.lists).insert(db.ListsCompanion.insert(kind: kind, value: v));
    }
  }

  Future<void> _writeSettings(StoreSettings s) async {
    final map = {
      'store_name': s.storeName,
      'currency': s.currency,
      'decimal_places': '${s.decimalPlaces}',
      'opening_cash': '${s.openingCash}',
      'low_stock': '${s.lowStock}',
    };
    for (final e in map.entries) {
      await _db.into(_db.settingsItems).insertOnConflictUpdate(
          db.SettingsItemsCompanion.insert(key: e.key, value: e.value));
    }
  }

  Future<void> _wipe() async {
    await _db.delete(_db.transactionLines).go();
    await _db.delete(_db.transactions).go();
    await _db.delete(_db.products).go();
    await _db.delete(_db.salespersons).go();
    await _db.delete(_db.lists).go();
    await _db.delete(_db.settingsItems).go();
  }

  // ---- Backup / restore (Section 12) ---------------------------------------

  Future<Map<String, dynamic>> exportBackup() async {
    final l = await loadLedger();
    final lists = await _db.select(_db.lists).get();
    return {
      'version': 1,
      'products': l.products
          .map((p) => {
                'id': p.id,
                'code': p.code,
                'name': p.name,
                'brand': p.brand,
                'category': p.category,
                'size': p.size,
                'buy_price': p.buyPrice,
                'sell_price': p.sellPrice,
                'archived': p.archived,
                'created_at': p.createdAt,
              })
          .toList(),
      'salespersons': l.salespersons
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'phone': s.phone,
                'opening': s.opening,
                'opening_margin_bp': s.openingMarginBp,
                'archived': s.archived,
                'created_at': s.createdAt,
              })
          .toList(),
      'transactions': l.txns
          .map((t) => {
                'id': t.id,
                'type': t.type.wire,
                'date': t.date,
                'created_at': t.createdAt,
                'salesperson_id': t.salespersonId,
                'product_id': t.productId,
                'qty': t.qty,
                'unit_buy': t.unitBuy,
                'amount': t.amount,
                'category': t.category,
                'recurring': t.recurring,
                'note': t.note,
                'lines': t.lines
                    .map((ln) => {
                          'id': ln.id,
                          'product_id': ln.productId,
                          'qty': ln.qty,
                          'unit_sell': ln.unitSell,
                          'unit_buy': ln.unitBuy,
                        })
                    .toList(),
              })
          .toList(),
      'lists': lists.map((r) => {'kind': r.kind, 'value': r.value}).toList(),
      'settings': {
        'store_name': l.settings.storeName,
        'currency': l.settings.currency,
        'decimal_places': l.settings.decimalPlaces,
        'opening_cash': l.settings.openingCash,
        'low_stock': l.settings.lowStock,
      },
    };
  }

  /// Validate the JSON shape before replacing data (Section 9.9).
  bool isValidBackup(Map<String, dynamic> json) =>
      json['products'] is List &&
      json['salespersons'] is List &&
      json['transactions'] is List &&
      json['settings'] is Map;

  Future<void> restoreBackup(Map<String, dynamic> json) async {
    if (!isValidBackup(json)) {
      throw DomainError('This file is not a valid backup.');
    }
    await _db.transaction(() async {
      await _wipe();
      for (final p in (json['products'] as List).cast<Map>()) {
        await _db.into(_db.products).insert(db.ProductsCompanion.insert(
              id: p['id'] as String,
              code: Value((p['code'] ?? '') as String),
              name: p['name'] as String,
              brand: Value((p['brand'] ?? '') as String),
              category: Value((p['category'] ?? '') as String),
              size: Value((p['size'] ?? '') as String),
              buyPrice: (p['buy_price'] as num).toInt(),
              sellPrice: (p['sell_price'] as num).toInt(),
              archived: Value((p['archived'] ?? false) as bool),
              createdAt: (p['created_at'] as num).toInt(),
            ));
      }
      for (final s in (json['salespersons'] as List).cast<Map>()) {
        await _db.into(_db.salespersons).insert(db.SalespersonsCompanion.insert(
              id: s['id'] as String,
              name: s['name'] as String,
              phone: Value((s['phone'] ?? '') as String),
              opening: Value((s['opening'] ?? 0) as int),
              openingMarginBp: Value((s['opening_margin_bp'] ?? 0) as int),
              archived: Value((s['archived'] ?? false) as bool),
              createdAt: (s['created_at'] as num).toInt(),
            ));
      }
      for (final t in (json['transactions'] as List).cast<Map>()) {
        await _db.into(_db.transactions).insert(db.TransactionsCompanion.insert(
              id: t['id'] as String,
              type: t['type'] as String,
              date: t['date'] as String,
              createdAt: (t['created_at'] as num).toInt(),
              salespersonId: Value(t['salesperson_id'] as String?),
              productId: Value(t['product_id'] as String?),
              qty: Value((t['qty'] as num?)?.toInt()),
              unitBuy: Value((t['unit_buy'] as num?)?.toInt()),
              amount: Value((t['amount'] as num?)?.toInt()),
              category: Value(t['category'] as String?),
              recurring: Value((t['recurring'] ?? false) as bool),
              note: Value(t['note'] as String?),
            ));
        for (final ln in ((t['lines'] ?? []) as List).cast<Map>()) {
          await _db.into(_db.transactionLines).insert(
              db.TransactionLinesCompanion.insert(
                  id: ln['id'] as String,
                  transactionId: t['id'] as String,
                  productId: ln['product_id'] as String,
                  qty: (ln['qty'] as num).toInt(),
                  unitSell: (ln['unit_sell'] as num).toInt(),
                  unitBuy: (ln['unit_buy'] as num).toInt()));
        }
      }
      for (final r in ((json['lists'] ?? []) as List).cast<Map>()) {
        await _db.into(_db.lists).insertOnConflictUpdate(db.ListsCompanion.insert(
            kind: r['kind'] as String, value: r['value'] as String));
      }
      final set = json['settings'] as Map;
      await _writeSettings(StoreSettings(
        storeName: (set['store_name'] ?? 'My Store') as String,
        currency: (set['currency'] ?? '') as String,
        decimalPlaces: (set['decimal_places'] as num?)?.toInt() ?? 0,
        openingCash: (set['opening_cash'] as num?)?.toInt() ?? 0,
        lowStock: (set['low_stock'] as num?)?.toInt() ?? 20,
      ));
    });
  }

  static String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
