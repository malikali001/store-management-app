import 'package:flutter_test/flutter_test.dart';
import 'package:store_manager/domain/models.dart';

void main() {
  test('TxnType wire round-trips and rejects unknown', () {
    for (final t in TxnType.values) {
      expect(TxnType.fromWire(t.wire), t);
    }
    expect(() => TxnType.fromWire('nope'), throwsArgumentError);
  });

  test('Product.copyWith changes only the given fields', () {
    const p = Product(id: 'p1', name: 'Tee', buyPrice: 100, sellPrice: 150, createdAt: 1);
    final e = p.copyWith(name: 'Cap', sellPrice: 200, archived: true);
    expect(e.id, 'p1');
    expect(e.name, 'Cap');
    expect(e.buyPrice, 100);
    expect(e.sellPrice, 200);
    expect(e.archived, isTrue);
    expect(e.createdAt, 1);
    // Untouched copy equals original values.
    expect(p.copyWith().name, 'Tee');
  });

  test('Salesperson.copyWith preserves id/createdAt', () {
    const s = Salesperson(id: 's1', name: 'Sam', createdAt: 5, opening: 100);
    final e = s.copyWith(name: 'Sammy', phone: '123', opening: 200);
    expect(e.id, 's1');
    expect(e.createdAt, 5);
    expect(e.name, 'Sammy');
    expect(e.phone, '123');
    expect(e.opening, 200);
  });

  test('Shop.copyWith updates fields', () {
    const shop = Shop(id: 'sh1', name: 'Mart', createdAt: 9);
    final e = shop.copyWith(name: 'Super Mart', ownerName: 'Ann', archived: true);
    expect(e.id, 'sh1');
    expect(e.name, 'Super Mart');
    expect(e.ownerName, 'Ann');
    expect(e.archived, isTrue);
    expect(e.createdAt, 9);
  });

  test('TxnLine and Txn line aggregates', () {
    const line = TxnLine(
        id: 'l1', transactionId: 't1', productId: 'p1', qty: 3, unitSell: 50, unitBuy: 30);
    expect(line.lineSell, 150);
    expect(line.lineBuy, 90);
    const txn = Txn(
      id: 't1',
      type: TxnType.sale,
      date: '2026-01-01',
      createdAt: 1,
      lines: [line],
    );
    expect(txn.linesSell, 150);
    expect(txn.linesBuy, 90);
  });

  test('ShopSegment labels are set', () {
    expect(ShopSegment.fresh.label, 'New');
    expect(ShopSegment.reliable.label, 'Reliable');
    expect(ShopSegment.inactive.label, 'Inactive');
    expect(ShopSegment.regular.label, 'Regular');
  });

  test('Txn.compare orders by date then createdAt', () {
    const a = Txn(id: 'a', type: TxnType.payment, date: '2026-01-01', createdAt: 2);
    const b = Txn(id: 'b', type: TxnType.payment, date: '2026-01-01', createdAt: 5);
    const c = Txn(id: 'c', type: TxnType.payment, date: '2026-01-02', createdAt: 1);
    final list = [c, b, a]..sort(Txn.compare);
    expect(list.map((t) => t.id).toList(), ['a', 'b', 'c']);
  });
}
