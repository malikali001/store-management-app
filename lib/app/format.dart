import 'package:intl/intl.dart';

import '../domain/models.dart';

/// Formats money (minor-unit integers) and numbers for display per settings.
/// Rounding happens only here — stored values are always exact integers.
class Money {
  final int decimalPlaces;
  final String currency;
  late final NumberFormat _fmt;

  Money(StoreSettings s)
      : decimalPlaces = s.decimalPlaces,
        currency = s.currency {
    _fmt = NumberFormat.decimalPatternDigits(decimalDigits: decimalPlaces);
  }

  /// Renders [minor] units as a grouped string, with the currency symbol.
  String format(int minor, {bool sign = false}) {
    final value = minor / _pow10(decimalPlaces);
    var s = _fmt.format(value);
    if (sign && minor > 0) s = '+$s';
    return currency.isEmpty ? s : '$currency$s';
  }

  /// Like [format] but always shows a leading sign for non-zero values.
  String signed(int minor) {
    if (minor == 0) return format(0);
    final body = format(minor.abs());
    return minor < 0 ? '−$body' : '+$body';
  }

  /// Parses user text (major units) into minor-unit integer. Returns null on
  /// invalid input.
  int? parse(String text) {
    final t = text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    return (v * _pow10(decimalPlaces)).round();
  }

  /// Initial text value for an editor field (major units, no grouping).
  String editValue(int minor) {
    final value = minor / _pow10(decimalPlaces);
    return value.toStringAsFixed(decimalPlaces);
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

final _plainInt = NumberFormat.decimalPattern();
String formatQty(int n) => _plainInt.format(n);

/// 'YYYY-MM-DD' → a friendly local label, e.g. "21 Jun 2026".
String prettyDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    return DateFormat('d MMM yyyy').format(d);
  } catch (_) {
    return iso;
  }
}

String todayIso() {
  final d = DateTime.now();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
