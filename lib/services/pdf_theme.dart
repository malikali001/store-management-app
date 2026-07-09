/// Shared PDF theme with bundled Roboto fonts.
///
/// The `pdf` package's built-in standard fonts (Helvetica) render blank on
/// Flutter web, so every generated document must embed a real TrueType font.
/// The fonts ship as bundled assets, keeping the app fully offline. Cached
/// after first load.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

pw.ThemeData? _cached;

Future<pw.ThemeData> loadPdfTheme() async {
  if (_cached != null) return _cached!;
  final regular =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  _cached = pw.ThemeData.withFont(base: regular, bold: bold);
  return _cached!;
}
