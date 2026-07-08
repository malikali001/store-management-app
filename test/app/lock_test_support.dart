import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:store_manager/security/lock_controller.dart';
import 'package:store_manager/security/lock_service.dart';
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

/// Provider override that runs the app lock against an in-memory store (lock is
/// simply off unless a test opts in), keeping the app fully rendered in tests.
Override lockTestOverride() =>
    lockServiceProvider.overrideWithValue(LockService(store: FakeSecureStore()));
