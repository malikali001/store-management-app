import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store_manager/security/lock_controller.dart';
import 'package:store_manager/security/lock_service.dart';
import 'package:store_manager/security/pin.dart';
import 'package:store_manager/security/secure_store.dart';

/// In-memory secure store so widget tests never touch the platform keystore
/// (flutter_secure_storage has no plugin under `flutter test`).
class FakeSecureStore extends SecureStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);
}

/// A LockService for tests: in-memory store plus SYNCHRONOUS PIN hashing.
/// Production offloads PBKDF2 to an isolate via compute(), but a widget test's
/// pumpAndSettle cannot drive a real isolate, so tests run it inline.
LockService fakeLockService() => LockService(
      store: FakeSecureStore(),
      hasher: (v) async => Pin.hash(v),
      verifier: (p, s) async => Pin.verify(p, s),
      biometricAvailableFn: () async => false,
    );

/// Provider override that runs the app lock against the test service (lock is
/// simply off unless a test opts in), keeping the app fully rendered in tests.
Override lockTestOverride() =>
    lockServiceProvider.overrideWithValue(fakeLockService());
