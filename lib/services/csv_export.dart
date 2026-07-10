import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/ui.dart';
import '../domain/models.dart';
import 'share/share_bytes.dart';

const _converter = ListToCsvConverter();

/// Builds CSV from [buildRows] (behind a progress dialog) and shares it.
Future<void> _shareCsv(
  BuildContext context,
  String filename,
  List<List<Object?>> Function() buildRows,
) async {
  try {
    final bytes = await runWithProgress(context, 'Preparing CSV…', () async {
      final csv = _converter.convert(buildRows());
      return Uint8List.fromList(utf8.encode(csv));
    });
    if (!context.mounted) return;
    await shareBytes(bytes, filename, 'text/csv');
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not export the file. Please try again.');
    }
  }
}

/// Products: code, name, brand, category, size, buy, sell, current stock.
Future<void> exportProductsCsv(BuildContext context, WidgetRef ref) async {
  final ledger = ref.read(ledgerProvider).valueOrNull;
  if (ledger == null) {
    showError(context, 'Data is not ready yet. Please try again.');
    return;
  }
  final money = ref.read(moneyProvider);

  await _shareCsv(context, 'products-${todayIso()}.csv', () {
    final rows = <List<Object?>>[
      ['Code', 'Name', 'Brand', 'Category', 'Size', 'Buy', 'Sell', 'Stock'],
    ];
    for (final p in ledger.products) {
      rows.add([
        p.code,
        p.name,
        p.brand,
        p.category,
        p.size,
        money.editValue(p.buyPrice),
        money.editValue(p.sellPrice),
        ledger.stock(p.id),
      ]);
    }
    return rows;
  });
}

/// Salespersons: name, goods taken (incl. opening), paid, owed, profit recognised.
Future<void> exportSalespersonsCsv(BuildContext context, WidgetRef ref) async {
  final ledger = ref.read(ledgerProvider).valueOrNull;
  if (ledger == null) {
    showError(context, 'Data is not ready yet. Please try again.');
    return;
  }
  final money = ref.read(moneyProvider);

  await _shareCsv(context, 'salespersons-${todayIso()}.csv', () {
    final rows = <List<Object?>>[
      ['Name', 'Goods taken', 'Paid', 'Owed', 'Profit recognised'],
    ];
    for (final s in ledger.salespersons) {
      final goodsTaken = s.opening + ledger.sellTaken(s.id);
      rows.add([
        s.name,
        money.editValue(goodsTaken),
        money.editValue(ledger.paymentsBy(s.id)),
        money.editValue(ledger.balance(s.id)),
        money.editValue(ledger.recognisedProfit(s.id)),
      ]);
    }
    return rows;
  });
}

/// Transactions: date, type, salesperson, detail, money-in, money-out.
/// Guards deleted product/salesperson names.
Future<void> exportTransactionsCsv(BuildContext context, WidgetRef ref) async {
  final ledger = ref.read(ledgerProvider).valueOrNull;
  if (ledger == null) {
    showError(context, 'Data is not ready yet. Please try again.');
    return;
  }
  final money = ref.read(moneyProvider);

  final txns = [...ledger.txns]..sort(Txn.compare);

  String spName(String? id) {
    if (id == null) return '';
    return ledger.salesperson(id)?.name ?? '(former salesperson)';
  }

  String productName(String id) {
    final p = ledger.product(id);
    if (p == null) return '(deleted product)';
    return p.size.isEmpty ? p.name : '${p.name} · ${p.size}';
  }

  String linesDetail(Txn t) {
    final pieces = t.lines.fold<int>(0, (s, l) => s + l.qty);
    final items =
        t.lines.map((l) => '${productName(l.productId)} ×${l.qty}').join(', ');
    return '$pieces pcs: $items';
  }

  String typeLabel(TxnType type) => switch (type) {
        TxnType.stockin => 'Stock in',
        TxnType.sale => 'Sale',
        TxnType.returnGoods => 'Return',
        TxnType.payment => 'Payment',
        TxnType.expense => 'Expense',
      };

  await _shareCsv(context, 'transactions-${todayIso()}.csv', () {
    final rows = <List<Object?>>[
      ['Date', 'Type', 'Salesperson', 'Detail', 'Money in', 'Money out'],
    ];

    for (final t in txns) {
    String detail = '';
    String moneyIn = '';
    String moneyOut = '';

    switch (t.type) {
      case TxnType.stockin:
        detail = '${productName(t.productId ?? '')} ×${t.qty ?? 0}';
        moneyOut = money.editValue((t.qty ?? 0) * (t.unitBuy ?? 0));
        break;
      case TxnType.sale:
        detail = linesDetail(t);
        break;
      case TxnType.returnGoods:
        detail = linesDetail(t);
        break;
      case TxnType.payment:
        detail = (t.note ?? '').trim();
        moneyIn = money.editValue(t.amount ?? 0);
        break;
      case TxnType.expense:
        final cat = (t.category ?? '').trim();
        final note = (t.note ?? '').trim();
        detail = note.isEmpty ? cat : '$cat — $note';
        moneyOut = money.editValue(t.amount ?? 0);
        break;
    }

    rows.add([
      t.date,
      typeLabel(t.type),
      spName(t.salespersonId),
      detail,
      moneyIn,
      moneyOut,
    ]);
    }

    return rows;
  });
}
