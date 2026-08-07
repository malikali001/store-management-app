/// Period boundaries (Section 6.6). Dates are local 'YYYY-MM-DD' strings.
library;

enum PeriodKind { month, quarter, allTime }

class Period {
  /// Inclusive lower bound, 'YYYY-MM-DD', or null for unbounded.
  final String? from;

  /// Inclusive upper bound, 'YYYY-MM-DD', or null for unbounded.
  final String? to;

  final PeriodKind kind;

  const Period({required this.from, required this.to, required this.kind});

  /// A transaction is "in period" if from <= date <= to (inclusive).
  /// ISO 'YYYY-MM-DD' strings compare correctly lexicographically.
  bool contains(String date) {
    if (from != null && date.compareTo(from!) < 0) return false;
    if (to != null && date.compareTo(to!) > 0) return false;
    return true;
  }

  static String _fmt(int year, int month, int day) {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  static String fmtDate(DateTime d) => _fmt(d.year, d.month, d.day);

  /// 'YYYY-MM-DD' shifted by [days] (negative goes back). Goes through
  /// [DateTime] so month and year boundaries are handled for us.
  static String shiftDays(String iso, int days) {
    final d = DateTime.parse(iso);
    return fmtDate(DateTime(d.year, d.month, d.day + days));
  }

  /// Whole calendar days from [fromIso] to [toIso] — 0 for the same day,
  /// negative when [toIso] is earlier. Time of day is ignored.
  static int daysBetween(String fromIso, String toIso) {
    final a = DateTime.parse(fromIso);
    final b = DateTime.parse(toIso);
    return DateTime(b.year, b.month, b.day)
        .difference(DateTime(a.year, a.month, a.day))
        .inDays;
  }

  /// [first day of current month, today], using device-local [now].
  static Period thisMonth(DateTime now) => Period(
        from: _fmt(now.year, now.month, 1),
        to: _fmt(now.year, now.month, now.day),
        kind: PeriodKind.month,
      );

  /// [first day of current calendar quarter, today], using local [now].
  static Period thisQuarter(DateTime now) {
    final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    return Period(
      from: _fmt(now.year, qStartMonth, 1),
      to: _fmt(now.year, now.month, now.day),
      kind: PeriodKind.quarter,
    );
  }

  static const Period allTime =
      Period(from: null, to: null, kind: PeriodKind.allTime);

  static Period forKind(PeriodKind kind, DateTime now) => switch (kind) {
        PeriodKind.month => thisMonth(now),
        PeriodKind.quarter => thisQuarter(now),
        PeriodKind.allTime => allTime,
      };
}
