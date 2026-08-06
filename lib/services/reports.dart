/// UI wrappers that generate a PDF report and hand it to the OS share/print
/// sheet. The heavy lifting (and all business math) is in report_pdf.dart.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/ui.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/period.dart';
import 'report_pdf.dart';

typedef _Builder = Future<Uint8List> Function(Ledger, StoreSettings, Period);

Future<void> _generate(BuildContext context, WidgetRef ref, String filename,
    _Builder build) async {
  try {
    final bytes = await runWithProgress(context, 'Generating report…', () async {
      // Load a fresh ledger so the report reflects the very latest data.
      final ledger = await ref.read(repositoryProvider).loadLedger();
      final period = ref.read(periodProvider);
      return build(ledger, ledger.settings, period);
    });
    if (!context.mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: filename);
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not generate the report. Please try again.');
    }
  }
}

Future<void> shareProductsReport(BuildContext context, WidgetRef ref) =>
    _generate(context, ref, 'products-report-${todayIso()}.pdf',
        buildProductsReportPdf);

Future<void> shareShopsReport(BuildContext context, WidgetRef ref) =>
    _generate(context, ref, 'shops-report-${todayIso()}.pdf',
        buildShopsReportPdf);

Future<void> shareSalespersonsReport(BuildContext context, WidgetRef ref) =>
    _generate(context, ref, 'salespersons-report-${todayIso()}.pdf',
        buildSalespersonsReportPdf);
