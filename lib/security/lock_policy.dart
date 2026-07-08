/// Brute-force throttling policy — pure Dart, unit-tested.
///
/// After a threshold of consecutive wrong PINs, the app imposes an escalating
/// cool-down so a thief cannot try thousands of PINs quickly. This is separate
/// from (and complements) the KDF cost in [Pin].
library;

class LockPolicy {
  /// Free attempts before any cool-down kicks in.
  static const int freeAttempts = 5;

  /// Hard cap on the cool-down (an hour).
  static const Duration maxLockout = Duration(hours: 1);

  /// Cool-down to impose given the number of *consecutive* failed attempts.
  /// 0–5 → none; then 30s, 60s, 120s, … doubling, capped at [maxLockout].
  static Duration lockoutFor(int consecutiveFailures) {
    if (consecutiveFailures <= freeAttempts) return Duration.zero;
    final over = consecutiveFailures - freeAttempts; // 1, 2, 3, …
    var seconds = 30;
    for (var i = 1; i < over; i++) {
      seconds *= 2;
      if (seconds >= maxLockout.inSeconds) return maxLockout;
    }
    final capped = seconds > maxLockout.inSeconds ? maxLockout.inSeconds : seconds;
    return Duration(seconds: capped);
  }

  /// Whether input is currently blocked, given the failure count and the time
  /// of the last failed attempt relative to [now].
  static bool isLockedOut(int consecutiveFailures, DateTime? lastFailure,
      DateTime now) {
    if (lastFailure == null) return false;
    final wait = lockoutFor(consecutiveFailures);
    if (wait == Duration.zero) return false;
    return now.isBefore(lastFailure.add(wait));
  }

  /// Remaining cool-down at [now] (zero if not locked out).
  static Duration remaining(int consecutiveFailures, DateTime? lastFailure,
      DateTime now) {
    if (lastFailure == null) return Duration.zero;
    final wait = lockoutFor(consecutiveFailures);
    final until = lastFailure.add(wait);
    return now.isBefore(until) ? until.difference(now) : Duration.zero;
  }
}
