import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';

/// Builds the PDF bytes for a sale receipt (Section 10).
///
/// Layout, top to bottom: store name; "Sale receipt"; short receipt number
/// (first 6 chars of id, uppercased); date; salesperson name; line-item table
/// (item · size, qty, unit sell, line total); sale total; then previous
/// balance, this sale (+), new balance owed. Never shows buy price/cost.
Future<Uint8List> buildReceiptPdf(
  Ledger ledger,
  Txn sale,
  Money money,
  StoreSettings settings,
) async {
  final doc = pw.Document();

  final spName =
      ledger.salesperson(sale.salespersonId ?? '')?.name ?? '(former salesperson)';
  final receiptNo = (sale.id.length >= 6 ? sale.id.substring(0, 6) : sale.id)
      .toUpperCase();

  final saleTotal = sale.linesSell;
  final previous = ledger.balanceBefore(sale.salespersonId ?? '', sale);
  final newBalance = previous + saleTotal;

  // Build line-item rows.
  final itemRows = <List<String>>[];
  for (final line in sale.lines) {
    final product = ledger.product(line.productId);
    String name;
    if (product == null) {
      name = '(deleted product)';
    } else {
      name = product.size.isEmpty ? product.name : '${product.name} · ${product.size}';
    }
    itemRows.add([
      name,
      formatQty(line.qty),
      money.format(line.unitSell),
      money.format(line.lineSell),
    ]);
  }

  pw.Widget summaryRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 11,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              settings.storeName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('Sale receipt',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('Receipt $receiptNo', style: const pw.TextStyle(fontSize: 10)),
            pw.Text(prettyDate(sale.date), style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.Text('Salesperson: $spName',
                style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const ['Item', 'Qty', 'Unit', 'Total'],
              data: itemRows,
              headerStyle: pw.TextStyle(
                  fontSize: 10, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF0ED)),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Sale total: ${money.format(saleTotal)}',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 0.5),
            summaryRow('Previous balance', money.format(previous)),
            summaryRow('This sale', '+${money.format(saleTotal)}'),
            summaryRow('New balance owed', money.format(newBalance), bold: true),
          ],
        );
      },
    ),
  );

  return doc.save();
}

/// Shows a summary sheet for a sale receipt with a "Share / print PDF" button.
///
/// Reads the current ledger snapshot, finds the sale by [saleTxnId], renders a
/// plain summary, and lets the user share/print the generated PDF.
Future<void> showReceiptSheet(
  BuildContext context,
  WidgetRef ref,
  String saleTxnId,
) async {
  // Load a fresh ledger from the database rather than the reactive stream:
  // the stream reloads asynchronously after a write, so right after saving a
  // sale its snapshot may not yet contain the new transaction.
  final ledger = await ref.read(repositoryProvider).loadLedger();

  Txn? sale;
  for (final t in ledger.txns) {
    if (t.id == saleTxnId) {
      sale = t;
      break;
    }
  }
  if (sale == null) {
    if (context.mounted) showError(context, 'This sale could not be found.');
    return;
  }
  if (!context.mounted) return;

  final money = ref.read(moneyProvider);
  final settings = ref.read(settingsProvider);
  final theSale = sale;

  final spName = ledger.salesperson(theSale.salespersonId ?? '')?.name ??
      '(former salesperson)';
  final receiptNo =
      (theSale.id.length >= 6 ? theSale.id.substring(0, 6) : theSale.id)
          .toUpperCase();
  final saleTotal = theSale.linesSell;
  final previous = ledger.balanceBefore(theSale.salespersonId ?? '', theSale);
  final newBalance = previous + saleTotal;

  Widget lineLabel(String left, String right, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(left,
                style: TextStyle(
                    color: color ?? AppColors.ink,
                    fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          ),
          Text(right,
              style: tabularFigures.copyWith(
                  color: color ?? AppColors.ink,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
        ],
      ),
    );
  }

  final itemWidgets = <Widget>[];
  for (final line in theSale.lines) {
    final product = ledger.product(line.productId);
    final name = product == null
        ? '(deleted product)'
        : (product.size.isEmpty
            ? product.name
            : '${product.name} · ${product.size}');
    itemWidgets.add(lineLabel(
      '$name  ×${formatQty(line.qty)}',
      money.format(line.lineSell),
    ));
  }

  await showAppSheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader('Sale receipt'),
        Text(settings.storeName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('Receipt $receiptNo · ${prettyDate(theSale.date)}',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 2),
        Text('Salesperson: $spName',
            style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...itemWidgets,
              const Divider(height: 20),
              lineLabel('Sale total', money.format(saleTotal), bold: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              lineLabel('Previous balance', money.format(previous)),
              lineLabel('This sale', '+${money.format(saleTotal)}',
                  color: AppColors.positive),
              const Divider(height: 20),
              lineLabel('New balance owed', money.format(newBalance),
                  color: AppColors.danger, bold: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.ios_share),
          label: const Text('Share / print PDF'),
          onPressed: () async {
            try {
              final bytes = await buildReceiptPdf(ledger, theSale, money, settings);
              await Printing.sharePdf(
                bytes: bytes,
                filename: 'receipt-$receiptNo.pdf',
              );
            } catch (e) {
              if (context.mounted) {
                showError(context, 'Could not generate the receipt PDF.');
              }
            }
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}
