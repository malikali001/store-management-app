/// Shared PDF fonts/theme with bundled Roboto.
///
/// The `pdf` package's built-in standard fonts (Helvetica) render blank on
/// Flutter web, so every generated document must embed a real TrueType font.
/// The fonts ship as bundled assets, keeping the app fully offline. Cached
/// after first load.
///
/// [loadPdfFonts] returns the raw bytes so they can be handed to a background
/// isolate (rootBundle is only available on the root isolate); [loadPdfTheme]
/// builds a theme for on-main-thread use (e.g. the small receipt).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

(Uint8List, Uint8List)? _fontBytes;
pw.ThemeData? _cached;

Future<(Uint8List, Uint8List)> loadPdfFonts() async {
  if (_fontBytes != null) return _fontBytes!;
  Uint8List load(ByteData d) =>
      d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);
  final regular = load(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = load(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  _fontBytes = (regular, bold);
  return _fontBytes!;
}

/// Build a [pw.ThemeData] from raw font bytes (safe to call inside an isolate).
pw.ThemeData pdfThemeFromBytes(Uint8List regular, Uint8List bold) =>
    pw.ThemeData.withFont(
      base: pw.Font.ttf(ByteData.sublistView(regular)),
      bold: pw.Font.ttf(ByteData.sublistView(bold)),
    );

Future<pw.ThemeData> loadPdfTheme() async {
  if (_cached != null) return _cached!;
  final (regular, bold) = await loadPdfFonts();
  _cached = pdfThemeFromBytes(regular, bold);
  return _cached!;
}
