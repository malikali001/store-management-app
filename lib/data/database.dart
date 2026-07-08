import 'package:drift/drift.dart';

import 'connection/connection.dart'
    if (dart.library.io) 'connection/native.dart'
    if (dart.library.js_interop) 'connection/web.dart';

part 'database.g.dart';

// ---- Tables (Section 4.2) ---------------------------------------------------

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get name => text()();
  TextColumn get brand => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant(''))();
  TextColumn get size => text().withDefault(const Constant(''))();
  IntColumn get buyPrice => integer()();
  IntColumn get sellPrice => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Salespersons extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  IntColumn get opening => integer().withDefault(const Constant(0))();
  IntColumn get openingMarginBp => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // 'stockin'|'sale'|'return'|'payment'|'expense'
  TextColumn get date => text()(); // 'YYYY-MM-DD'
  IntColumn get createdAt => integer()();
  TextColumn get salespersonId => text().nullable()();
  TextColumn get productId => text().nullable()();
  IntColumn get qty => integer().nullable()();
  IntColumn get unitBuy => integer().nullable()();
  IntColumn get amount => integer().nullable()();
  TextColumn get category => text().nullable()();
  BoolColumn get recurring => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionLines extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get productId => text()();
  IntColumn get qty => integer()();
  IntColumn get unitSell => integer()();
  IntColumn get unitBuy => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Shops extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get ownerName => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class ShopPurchases extends Table {
  TextColumn get id => text()();
  TextColumn get shopId => text()();
  TextColumn get salespersonId => text().nullable()(); // optional staff link
  TextColumn get date => text()(); // 'YYYY-MM-DD'
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ListEntry')
class Lists extends Table {
  TextColumn get kind => text()(); // 'category'|'brand'|'size'|'expense_category'
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {kind, value};
}

class SettingsItems extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ---- Database ---------------------------------------------------------------

@DriftDatabase(tables: [
  Products,
  Salespersons,
  Transactions,
  TransactionLines,
  Shops,
  ShopPurchases,
  Lists,
  SettingsItems,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? openConnection());

  @override
  int get schemaVersion => 2;

  Future<void> _createShopIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_shop ON shop_purchases(shop_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_purchase_date ON shop_purchases(date)');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Indexes (edge case 10: keep derivations efficient).
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_txn_type ON transactions(type)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_txn_sp ON transactions(salesperson_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions(date)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_line_product ON transaction_lines(product_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_line_txn ON transaction_lines(transaction_id)');
          await _createShopIndexes();
        },
        onUpgrade: (m, from, to) async {
          // v2: shops (external customers) and their purchase log.
          if (from < 2) {
            await m.createTable(shops);
            await m.createTable(shopPurchases);
            await _createShopIndexes();
          }
        },
      );
}
