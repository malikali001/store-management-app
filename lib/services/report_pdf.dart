/// PDF report builders (Section 7.11, extended). Three comprehensive reports:
///  1. Products & inventory — stock, prices, stock value, units sold, revenue,
///     gross margin, low-stock list.
///  2. Shops — buying behaviour, segments, totals, and a full purchase log.
///  3. Salespersons — goods taken, paid, balance, recognised profit, plus each
///     person's full movement history.
///
/// Pure builders (no BuildContext) so they can be unit-tested; the sharing
/// wrappers live in reports.dart. All money is formatted for humans (grouping +
/// currency), never raw. Buy prices/costs appear here because reports are for
/// the owner — unlike customer receipts, which hide cost.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/format.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import 'pdf_theme.dart';

const _green = PdfColor.fromInt(0xFF157A5E);
const _ink = PdfColor.fromInt(0xFF1C211F);
const _muted = PdfColor.fromInt(0xFF6C726F);
const _headFill = PdfColor.fromInt(0xFFEEF0ED);
const _hairline = PdfColor.fromInt(0xFFE4E7E4);

// ---- Shared building blocks -------------------------------------------------

String _periodText(Period p) {
  switch (p.kind) {
    case PeriodKind.month:
      return 'This month (${prettyDate(p.from!)} – ${prettyDate(p.to!)})';
    case PeriodKind.quarter:
      return 'This quarter (${prettyDate(p.from!)} – ${prettyDate(p.to!)})';
    case PeriodKind.allTime:
      return 'All time';
  }
}

pw.Widget _titleBlock(String store, String title, Period period, DateTime now) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(store,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(title,
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green)),
      pw.SizedBox(height: 4),
      pw.Text('Period: ${_periodText(period)}',
          style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.Text('Generated: ${prettyDate(Period.fmtDate(now))}',
          style: const pw.TextStyle(fontSize: 10, color: _muted)),
      pw.SizedBox(height: 10),
      pw.Divider(thickness: 0.5, color: _hairline),
    ],
  );
}

pw.Widget _sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );

/// A compact key/value summary block.
pw.Widget _summary(List<(String, String)> rows) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _headFill,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      children: [
        for (final r in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(r.$1,
                    style: const pw.TextStyle(fontSize: 10, color: _muted)),
                pw.Text(r.$2,
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
      ],
    ),
  );
}

/// A table where [rightCols] indices are right-aligned (numbers). If [footer]
/// is given it is rendered as a bold totals row.
pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  Set<int> rightCols = const {},
  List<String>? footer,
}) {
  final aligns = <int, pw.Alignment>{
    for (var i = 0; i < headers.length; i++)
      i: rightCols.contains(i)
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
  };
  final data = [...rows, ?footer];
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    border: pw.TableBorder.all(color: _hairline, width: 0.5),
    headerStyle: pw.TextStyle(
        fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink),
    headerDecoration: const pw.BoxDecoration(color: _headFill),
    cellStyle: const pw.TextStyle(fontSize: 8.5),
    cellAlignments: aligns,
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  );
}

pw.Widget _muteNote(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(text,
          style: const pw.TextStyle(fontSize: 9, color: _muted)),
    );

pw.Widget _footer(pw.Context ctx) => pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted)),
    );

String _itemLabel(Ledger l, String productId) {
  final p = l.product(productId);
  if (p == null) return '(deleted product)';
  return p.size.isEmpty ? p.name : '${p.name} · ${p.size}';
}

// ---- 1. Products & inventory ------------------------------------------------

Future<Uint8List> buildProductsReportPdf(
  Ledger ledger,
  Money money,
  StoreSettings settings,
  Period period, {
  DateTime? generatedAt,
}) async {
  final now = generatedAt ?? DateTime.now();
  final doc = pw.Document(theme: await loadPdfTheme());

  final active = ledger.products.where((p) => !p.archived).toList()
    ..sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.size.compareTo(b.size);
    });

  // Group products by category, so the report reads section-by-section.
  final byCat = <String, List<Product>>{};
  for (final p in active) {
    final cat = p.category.trim().isEmpty ? 'Uncategorised' : p.category.trim();
    (byCat[cat] ??= []).add(p);
  }
  final categories = byCat.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  const headers = [
    'Code', 'Item', 'Brand', 'Buy', 'Sell', 'Stock', 'Stock value',
    'Sold', 'Revenue', 'Margin',
  ];
  const rightCols = {3, 4, 5, 6, 7, 8, 9};

  var totalUnits = 0;
  var totalRevenue = 0;
  var totalMargin = 0;
  final productSections = <pw.Widget>[];

  for (final cat in categories) {
    var cUnits = 0;
    var cStockValue = 0;
    var cRevenue = 0;
    var cMargin = 0;
    final rows = <List<String>>[];
    for (final p in byCat[cat]!) {
      final stock = ledger.stock(p.id);
      final stockVal = stock > 0 ? stock * p.buyPrice : 0;
      final sold = ledger.unitsSold(p.id);
      final revenue = ledger.salesRevenue(p.id);
      final margin = ledger.productGrossMargin(p.id);
      final low = stock <= settings.lowStock;
      if (stock > 0) {
        cUnits += stock;
        totalUnits += stock;
      }
      cStockValue += stockVal;
      cRevenue += revenue;
      totalRevenue += revenue;
      cMargin += margin;
      totalMargin += margin;
      rows.add([
        p.code,
        _itemLabel(ledger, p.id),
        p.brand,
        money.format(p.buyPrice),
        money.format(p.sellPrice),
        '${formatQty(stock)}${low ? ' *' : ''}',
        money.format(stockVal),
        formatQty(sold),
        money.format(revenue),
        money.format(margin),
      ]);
    }
    productSections.add(pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('$cat  (${byCat[cat]!.length})'),
        _table(headers, rows, rightCols: rightCols, footer: [
          'Subtotal', '', '', '', '', formatQty(cUnits),
          money.format(cStockValue), '', money.format(cRevenue),
          money.format(cMargin),
        ]),
      ],
    ));
  }

  final lowItems = ledger.lowStockProducts()
    ..sort((a, b) => ledger.stock(a.id).compareTo(ledger.stock(b.id)));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    footer: _footer,
    build: (ctx) => [
      _titleBlock(settings.storeName, 'Products & inventory report', period, now),
      _summary([
        ('Active products', formatQty(active.length)),
        ('Units in stock', formatQty(totalUnits)),
        ('Stock value (at cost)', money.format(ledger.stockValue)),
        ('Low-stock items (≤ ${settings.lowStock})',
            formatQty(lowItems.length)),
        ('Revenue (all time, net of returns)', money.format(totalRevenue)),
        ('Gross margin (all time)', money.format(totalMargin)),
      ]),
      _sectionTitle('Products by category'),
      if (productSections.isEmpty)
        _muteNote('No products yet.')
      else
        ...productSections,
      _muteNote(
          '* = at or below the low-stock threshold. Revenue and margin are '
          'lifetime figures using the price recorded at the time of each sale. '
          'Margin = revenue − cost of goods sold (not cash-basis profit).'),
      _sectionTitle('Low-stock items'),
      if (lowItems.isEmpty)
        _muteNote('Nothing at or below the threshold.')
      else
        _table(
          const ['Item', 'Code', 'In stock', 'Threshold'],
          [
            for (final p in lowItems)
              [
                _itemLabel(ledger, p.id),
                p.code,
                formatQty(ledger.stock(p.id)),
                formatQty(settings.lowStock),
              ],
          ],
          rightCols: {2, 3},
        ),
    ],
  ));

  return doc.save();
}

// ---- 2. Shops (external customers) ------------------------------------------

Future<Uint8List> buildShopsReportPdf(
  Ledger ledger,
  Money money,
  StoreSettings settings,
  Period period, {
  DateTime? generatedAt,
}) async {
  final now = generatedAt ?? DateTime.now();
  final doc = pw.Document(theme: await loadPdfTheme());

  final active = ledger.shops.where((s) => !s.archived).toList()
    ..sort((a, b) =>
        ledger.totalBought(b.id).compareTo(ledger.totalBought(a.id)));

  var totalAll = 0;
  var totalPeriod = 0;
  final rows = <List<String>>[];
  for (final s in active) {
    final all = ledger.totalBought(s.id);
    final inPeriod = ledger.boughtInPeriod(s.id, period);
    totalAll += all;
    totalPeriod += inPeriod;
    final first = ledger.firstPurchaseDate(s.id);
    final last = ledger.lastPurchaseDate(s.id);
    rows.add([
      s.name,
      s.ownerName,
      s.phone,
      ledger.shopSegment(s.id, now).label,
      formatQty(ledger.purchaseCount(s.id)),
      first == null ? '—' : prettyDate(first),
      last == null ? '—' : prettyDate(last),
      money.format(all),
      money.format(inPeriod),
    ]);
  }

  // Full purchase log, newest first.
  final purchases = [...ledger.shopPurchases]
    ..sort((a, b) => ShopPurchase.compare(b, a));

  String shopName(String id) => ledger.shop(id)?.name ?? '(removed shop)';
  String spName(String? id) =>
      id == null ? '' : (ledger.salesperson(id)?.name ?? '(former salesperson)');

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    footer: _footer,
    build: (ctx) => [
      _titleBlock(settings.storeName, 'Shops (customers) report', period, now),
      _summary([
        ('Active shops', formatQty(active.length)),
        ('Total bought (all time)', money.format(totalAll)),
        ('Bought in period', money.format(totalPeriod)),
        ('Recorded purchases', formatQty(ledger.shopPurchases.length)),
      ]),
      _sectionTitle('Shops (ranked by total bought)'),
      if (rows.isEmpty)
        _muteNote('No shops yet.')
      else
        _table(
          const [
            'Shop', 'Owner', 'Phone', 'Segment', 'Buys', 'First', 'Last',
            'Total bought', 'In period',
          ],
          rows,
          rightCols: {4, 7, 8},
          footer: [
            'Totals', '', '', '', '', '', '',
            money.format(totalAll), money.format(totalPeriod),
          ],
        ),
      _sectionTitle('Purchase log (newest first)'),
      if (purchases.isEmpty)
        _muteNote('No purchases recorded.')
      else
        _table(
          const ['Date', 'Shop', 'Salesperson', 'Amount', 'Note'],
          [
            for (final p in purchases)
              [
                prettyDate(p.date),
                shopName(p.shopId),
                spName(p.salespersonId),
                money.format(p.amount),
                (p.note ?? '').trim(),
              ],
          ],
          rightCols: {3},
        ),
    ],
  ));

  return doc.save();
}

// ---- 3. Salespersons --------------------------------------------------------

Future<Uint8List> buildSalespersonsReportPdf(
  Ledger ledger,
  Money money,
  StoreSettings settings,
  Period period, {
  DateTime? generatedAt,
}) async {
  final now = generatedAt ?? DateTime.now();
  final doc = pw.Document(theme: await loadPdfTheme());

  final people = [...ledger.salespersons]
    ..sort((a, b) => ledger.balance(b.id).compareTo(ledger.balance(a.id)));

  var totalTaken = 0;
  var totalPaid = 0;
  var totalOwed = 0;
  var totalProfit = 0;
  final rows = <List<String>>[];
  for (final s in people) {
    final taken = s.opening + ledger.sellTaken(s.id);
    final paid = ledger.paymentsBy(s.id);
    final owed = ledger.balance(s.id);
    final profit = ledger.recognisedProfit(s.id);
    totalTaken += taken;
    totalPaid += paid;
    totalOwed += owed;
    totalProfit += profit;
    rows.add([
      s.name,
      s.phone,
      money.format(s.opening),
      money.format(taken),
      money.format(paid),
      money.format(owed),
      money.format(profit),
      money.format(ledger.takenInPeriod(s.id, period)),
    ]);
  }

  // Per-person movement detail.
  final detailSections = <pw.Widget>[];
  for (final s in people) {
    final events = ledger.txns
        .where((t) =>
            t.salespersonId == s.id &&
            (t.type == TxnType.sale ||
                t.type == TxnType.returnGoods ||
                t.type == TxnType.payment))
        .toList()
      ..sort(Txn.compare);

    final detailRows = <List<String>>[];
    if (s.opening != 0) {
      detailRows.add(
          ['—', 'Opening balance', '', money.format(s.opening)]);
    }
    for (final t in events) {
      switch (t.type) {
        case TxnType.sale:
          detailRows.add([
            prettyDate(t.date),
            'Took goods',
            _linesSummary(ledger, t),
            '+${money.format(t.linesSell)}',
          ]);
          break;
        case TxnType.returnGoods:
          detailRows.add([
            prettyDate(t.date),
            'Returned goods',
            _linesSummary(ledger, t),
            '−${money.format(t.linesSell)}',
          ]);
          break;
        case TxnType.payment:
          detailRows.add([
            prettyDate(t.date),
            'Payment received',
            (t.note ?? '').trim(),
            '−${money.format(t.amount ?? 0)}',
          ]);
          break;
        default:
          break;
      }
    }

    detailSections.add(pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('${s.name} — balance owed ${money.format(ledger.balance(s.id))}'),
        if (detailRows.isEmpty)
          _muteNote('No movements yet.')
        else
          _table(
            const ['Date', 'Type', 'Detail', 'Amount'],
            detailRows,
            rightCols: {3},
          ),
      ],
    ));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    footer: _footer,
    build: (ctx) => [
      _titleBlock(settings.storeName, 'Salespersons report', period, now),
      _summary([
        ('Salespersons', formatQty(people.length)),
        ('Goods taken (all time, incl. opening)', money.format(totalTaken)),
        ('Money collected (all time)', money.format(totalPaid)),
        ('Outstanding balance (now)', money.format(totalOwed)),
        ('Recognised profit (all time)', money.format(totalProfit)),
        ('Recognised profit (period)',
            money.format(ledger.recognisedProfitInPeriod(period))),
      ]),
      _sectionTitle('Summary (ranked by balance owed)'),
      if (rows.isEmpty)
        _muteNote('No salespersons yet.')
      else
        _table(
          const [
            'Name', 'Phone', 'Opening', 'Goods taken', 'Paid', 'Owed',
            'Profit', 'Taken (period)',
          ],
          rows,
          rightCols: {2, 3, 4, 5, 6, 7},
          footer: [
            'Totals', '', '', money.format(totalTaken), money.format(totalPaid),
            money.format(totalOwed), money.format(totalProfit), '',
          ],
        ),
      _muteNote(
          'Profit is recognised on a cash basis as payments arrive, split '
          'proportionally to each person’s blended margin (spec 6.5).'),
      pw.SizedBox(height: 6),
      _sectionTitle('Movement detail'),
      ...detailSections,
    ],
  ));

  return doc.save();
}

String _linesSummary(Ledger l, Txn t) {
  final pieces = t.lines.fold<int>(0, (s, line) => s + line.qty);
  final items =
      t.lines.map((line) => '${_itemLabel(l, line.productId)} ×${line.qty}').join(', ');
  return '$pieces pcs: $items';
}
