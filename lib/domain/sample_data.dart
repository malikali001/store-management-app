/// Appendix A golden sample data. Used to seed the app on first run and as the
/// unit-test fixture. Pure Dart so tests can build a [Ledger] without Flutter.
library;

import 'models.dart';

class SampleData {
  /// Settings per Appendix A: currency empty, 0 decimals, opening cash 150000,
  /// low-stock threshold 20.
  static const settings = StoreSettings(
    storeName: 'My Store',
    currency: '',
    decimalPlaces: 0,
    openingCash: 150000,
    lowStock: 20,
  );

  static List<Product> products(int createdAt) => [
        Product(id: 'p_tsm', code: 'TS-M', name: 'Cotton tee', brand: 'Acme', category: 'T-shirts', size: 'M', buyPrice: 180, sellPrice: 250, createdAt: createdAt),
        Product(id: 'p_tsl', code: 'TS-L', name: 'Cotton tee', brand: 'Acme', category: 'T-shirts', size: 'L', buyPrice: 180, sellPrice: 250, createdAt: createdAt),
        Product(id: 'p_tsxl', code: 'TS-XL', name: 'Cotton tee', brand: 'Acme', category: 'T-shirts', size: 'XL', buyPrice: 190, sellPrice: 270, createdAt: createdAt),
        Product(id: 'p_sh7', code: 'SH-7', name: 'Runner shoe', brand: 'Nova', category: 'Footwear', size: '7', buyPrice: 900, sellPrice: 1200, createdAt: createdAt),
        Product(id: 'p_sh8', code: 'SH-8', name: 'Runner shoe', brand: 'Nova', category: 'Footwear', size: '8', buyPrice: 900, sellPrice: 1200, createdAt: createdAt),
        Product(id: 'p_cps', code: 'CP-S', name: 'Logo cap', brand: 'Acme', category: 'Caps', size: 'Std', buyPrice: 90, sellPrice: 150, createdAt: createdAt),
      ];

  static List<Salesperson> salespersons(int createdAt) => [
        Salesperson(id: 's_rahul', name: 'Rahul', createdAt: createdAt),
        Salesperson(id: 's_amir', name: 'Amir', createdAt: createdAt),
        Salesperson(id: 's_sana', name: 'Sana', createdAt: createdAt),
      ];

  /// Builds the full transaction ledger. [date] is the local date string used
  /// for every entry (Appendix A treats all dates as within the current month).
  /// [base] is the starting epoch-ms for createdAt; each entry increments it so
  /// that sales precede returns precede payments (ordering matters for profit).
  static List<Txn> transactions(String date, int base) {
    var clock = base;
    int next() => clock += 1000;

    TxnLine line(String txnId, String pid, int qty, int sell, int buy) =>
        TxnLine(id: '${txnId}_$pid', transactionId: txnId, productId: pid, qty: qty, unitSell: sell, unitBuy: buy);

    final out = <Txn>[];

    // Stock in
    final stockins = [
      ('p_tsm', 100, 180),
      ('p_tsl', 80, 180),
      ('p_tsxl', 40, 190),
      ('p_sh7', 30, 900),
      ('p_sh8', 25, 900),
      ('p_cps', 200, 90),
    ];
    for (final (pid, qty, buy) in stockins) {
      out.add(Txn(id: 'si_$pid', type: TxnType.stockin, date: date, createdAt: next(), productId: pid, qty: qty, unitBuy: buy));
    }

    // Sales
    out.add(Txn(id: 'sale_rahul', type: TxnType.sale, date: date, createdAt: next(), salespersonId: 's_rahul', lines: [
      line('sale_rahul', 'p_tsm', 40, 250, 180),
      line('sale_rahul', 'p_cps', 50, 150, 90),
    ]));
    out.add(Txn(id: 'sale_amir', type: TxnType.sale, date: date, createdAt: next(), salespersonId: 's_amir', lines: [
      line('sale_amir', 'p_sh7', 10, 1200, 900),
      line('sale_amir', 'p_sh8', 8, 1200, 900),
    ]));
    out.add(Txn(id: 'sale_sana', type: TxnType.sale, date: date, createdAt: next(), salespersonId: 's_sana', lines: [
      line('sale_sana', 'p_tsl', 20, 250, 180),
    ]));

    // Return
    out.add(Txn(id: 'ret_rahul', type: TxnType.returnGoods, date: date, createdAt: next(), salespersonId: 's_rahul', lines: [
      line('ret_rahul', 'p_cps', 10, 150, 90),
    ]));

    // Payments
    out.add(Txn(id: 'pay_rahul', type: TxnType.payment, date: date, createdAt: next(), salespersonId: 's_rahul', amount: 10000));
    out.add(Txn(id: 'pay_amir', type: TxnType.payment, date: date, createdAt: next(), salespersonId: 's_amir', amount: 16000));
    out.add(Txn(id: 'pay_sana', type: TxnType.payment, date: date, createdAt: next(), salespersonId: 's_sana', amount: 3000));

    // Expenses
    out.add(Txn(id: 'exp_rent', type: TxnType.expense, date: date, createdAt: next(), category: 'Rent', amount: 3000));
    out.add(Txn(id: 'exp_transport', type: TxnType.expense, date: date, createdAt: next(), category: 'Transport', amount: 1200));
    out.add(Txn(id: 'exp_labour', type: TxnType.expense, date: date, createdAt: next(), category: 'Labour', amount: 2000));

    return out;
  }
}
