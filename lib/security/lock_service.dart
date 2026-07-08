/// Runtime app-lock logic: configure/verify the PIN, biometric unlock, and
/// brute-force throttling. Combines [SecureStore], [Pin], [LockPolicy] and
/// local_auth. Plugin calls (secure storage, biometrics) only run on-device.
library;

import 'package:local_auth/local_auth.dart';

import 'lock_policy.dart';
import 'pin.dart';
import 'secure_store.dart';

/// Result of a PIN attempt.
enum PinResult { ok, wrong, lockedOut }

class LockService {
  final SecureStore _store;
  final LocalAuthentication _auth;

  LockService({SecureStore? store, LocalAuthentication? auth})
      : _store = store ?? SecureStore(),
        _auth = auth ?? LocalAuthentication();

  /// Whether a PIN has ever been set (lock is available to turn on).
  Future<bool> isConfigured() async =>
      (await _store.read(SecureStore.kPinHash)) != null;

  /// Whether the lock is currently switched on.
  Future<bool> isEnabled() async =>
      (await _store.read(SecureStore.kLockEnabled)) == '1' &&
      await isConfigured();

  Future<bool> isBiometricPreferred() async =>
      (await _store.read(SecureStore.kBiometricEnabled)) == '1';

  /// Minutes of background before the app re-locks (0 = lock immediately).
  Future<int> autoLockMinutes() async =>
      int.tryParse(await _store.read(SecureStore.kAutoLockMinutes) ?? '') ?? 0;

  Future<void> setAutoLockMinutes(int m) =>
      _store.write(SecureStore.kAutoLockMinutes, '$m');

  /// Set (or change) the PIN and switch the lock on. Resets failure counters.
  Future<void> setPin(String pin) async {
    await _store.write(SecureStore.kPinHash, Pin.hash(pin));
    await _store.write(SecureStore.kLockEnabled, '1');
    await _resetFailures();
  }

  /// Turn the lock off and forget the PIN/biometric preference.
  Future<void> disable() async {
    await _store.delete(SecureStore.kPinHash);
    await _store.write(SecureStore.kLockEnabled, '0');
    await _store.delete(SecureStore.kBiometricEnabled);
    await _resetFailures();
  }

  Future<void> setBiometricPreferred(bool on) =>
      _store.write(SecureStore.kBiometricEnabled, on ? '1' : '0');

  // ---- Throttling ----------------------------------------------------------

  Future<int> _failedAttempts() async =>
      int.tryParse(await _store.read(SecureStore.kFailedAttempts) ?? '') ?? 0;

  Future<DateTime?> _lastFailure() async {
    final ms = int.tryParse(await _store.read(SecureStore.kLastFailureMs) ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _resetFailures() async {
    await _store.write(SecureStore.kFailedAttempts, '0');
    await _store.delete(SecureStore.kLastFailureMs);
  }

  /// Cool-down remaining right now (zero if input is allowed).
  Future<Duration> lockoutRemaining({DateTime? now}) async {
    return LockPolicy.remaining(
        await _failedAttempts(), await _lastFailure(), now ?? DateTime.now());
  }

  /// Verify a PIN, applying throttling. On success, counters reset.
  Future<PinResult> verifyPin(String pin, {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final attempts = await _failedAttempts();
    final last = await _lastFailure();
    if (LockPolicy.isLockedOut(attempts, last, ts)) return PinResult.lockedOut;

    final stored = await _store.read(SecureStore.kPinHash);
    if (stored != null && Pin.verify(pin, stored)) {
      await _resetFailures();
      return PinResult.ok;
    }
    await _store.write(SecureStore.kFailedAttempts, '${attempts + 1}');
    await _store.write(
        SecureStore.kLastFailureMs, '${ts.millisecondsSinceEpoch}');
    return PinResult.wrong;
  }

  // ---- Biometrics ----------------------------------------------------------

  /// True if the device has enrolled biometrics we can use. Bounded by a short
  /// timeout so a wedged/absent biometric API can never freeze the UI.
  Future<bool> biometricAvailable() async {
    const t = Duration(seconds: 2);
    try {
      final supported =
          await _auth.isDeviceSupported().timeout(t, onTimeout: () => false);
      if (!supported) return false;
      final canCheck =
          await _auth.canCheckBiometrics.timeout(t, onTimeout: () => false);
      final types = await _auth
          .getAvailableBiometrics()
          .timeout(t, onTimeout: () => const <BiometricType>[]);
      return canCheck && types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Prompt for biometric unlock. Returns true only on a successful scan.
  Future<bool> authenticateBiometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Store Manager',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (ok) await _resetFailures();
      return ok;
    } catch (_) {
      return false;
    }
  }
}
