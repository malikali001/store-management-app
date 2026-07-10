/// Runtime app-lock logic: configure/verify the PIN, biometric unlock, and
/// brute-force throttling. Combines [SecureStore], [Pin], [LockPolicy] and
/// local_auth. Plugin calls (secure storage, biometrics) only run on-device.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show compute;
import 'package:local_auth/local_auth.dart';

import 'lock_policy.dart';
import 'pin.dart';
import 'secure_store.dart';

// Run the expensive PBKDF2 (120k iterations) on a background isolate so the UI
// thread never freezes while a PIN is set or checked.
String _hashOnIsolate(String value) => Pin.hash(value);
bool _verifyOnIsolate((String, String) args) => Pin.verify(args.$1, args.$2);

/// Result of a PIN attempt.
enum PinResult { ok, wrong, lockedOut }

class LockService {
  final SecureStore _store;
  final LocalAuthentication _auth;

  // PIN hashing runs on a background isolate in production (so the UI never
  // freezes). Tests inject synchronous versions because a widget test's
  // pumpAndSettle cannot drive a real isolate.
  final Future<String> Function(String) _hash;
  final Future<bool> Function(String, String) _verify;

  // Injectable so tests can resolve biometric availability instantly instead of
  // waiting on the (plugin-less) 2s timeout.
  final Future<bool> Function()? _biometricAvailableFn;

  LockService({
    SecureStore? store,
    LocalAuthentication? auth,
    Future<String> Function(String)? hasher,
    Future<bool> Function(String, String)? verifier,
    Future<bool> Function()? biometricAvailableFn,
  })  : _store = store ?? SecureStore(),
        _auth = auth ?? LocalAuthentication(),
        _hash = hasher ?? ((v) => compute(_hashOnIsolate, v)),
        _verify = verifier ?? ((p, s) => compute(_verifyOnIsolate, (p, s))),
        _biometricAvailableFn = biometricAvailableFn;

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
    await _store.write(SecureStore.kPinHash, await _hash(pin));
    await _store.write(SecureStore.kLockEnabled, '1');
    await _resetFailures();
  }

  /// Turn the lock off and forget the PIN/biometric preference.
  Future<void> disable() async {
    await _store.delete(SecureStore.kPinHash);
    await _store.delete(SecureStore.kRecoveryHash);
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

  Future<void> _recordFailure(int attempts, DateTime ts) async {
    await _store.write(SecureStore.kFailedAttempts, '${attempts + 1}');
    await _store.write(
        SecureStore.kLastFailureMs, '${ts.millisecondsSinceEpoch}');
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
    if (stored != null && await _verify(pin, stored)) {
      await _resetFailures();
      return PinResult.ok;
    }
    await _recordFailure(attempts, ts);
    return PinResult.wrong;
  }

  // ---- Recovery code -------------------------------------------------------
  //
  // A recovery code lets the owner reset a forgotten PIN without losing data.
  // It is a high-entropy secret shown once at setup for the user to save; only
  // its hash is stored (same PBKDF2 as the PIN), so it is a genuine second
  // credential, not a backdoor.

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no I,L,O,0,1
  static const _codeLen = 12; // ~59 bits of entropy

  /// Generate a fresh recovery code, formatted in groups for readability
  /// (e.g. "A7KM-3QRT-9XYZ"). Does not store anything.
  String generateRecoveryCode() {
    final rng = Random.secure();
    final chars = [
      for (var i = 0; i < _codeLen; i++) _alphabet[rng.nextInt(_alphabet.length)],
    ];
    final buf = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(chars[i]);
    }
    return buf.toString();
  }

  /// Normalise user input: uppercase, keep only A–Z/0–9 (so hyphens/spaces and
  /// case do not matter when typing the code).
  static String normaliseRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  Future<bool> hasRecoveryCode() async =>
      (await _store.read(SecureStore.kRecoveryHash)) != null;

  /// Store the hash of [code]. Call with the code shown to the user at setup.
  Future<void> setRecoveryCode(String code) async => _store.write(
      SecureStore.kRecoveryHash, await _hash(normaliseRecoveryCode(code)));

  /// Verify a recovery [code] and, if correct, set [newPin] (keeping the lock
  /// on). Applies the same throttling as PIN entry.
  Future<PinResult> resetPinWithRecovery(String code, String newPin,
      {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final attempts = await _failedAttempts();
    final last = await _lastFailure();
    if (LockPolicy.isLockedOut(attempts, last, ts)) return PinResult.lockedOut;

    final stored = await _store.read(SecureStore.kRecoveryHash);
    if (stored != null &&
        await _verify(normaliseRecoveryCode(code), stored)) {
      await setPin(newPin); // sets new PIN, keeps lock on, resets failures
      return PinResult.ok;
    }
    await _recordFailure(attempts, ts);
    return PinResult.wrong;
  }

  // ---- Biometrics ----------------------------------------------------------

  /// True if the device has enrolled biometrics we can use.
  Future<bool> biometricAvailable() =>
      _biometricAvailableFn?.call() ?? _realBiometricAvailable();

  /// Bounded by a short timeout so a wedged/absent biometric API can never
  /// freeze the UI.
  Future<bool> _realBiometricAvailable() async {
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
