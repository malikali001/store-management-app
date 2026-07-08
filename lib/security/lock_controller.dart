/// Riverpod state for the app lock: whether the app is currently locked, and
/// the actions to lock/unlock. The [LockGate] widget renders the lock screen
/// whenever [LockState.locked] is true.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lock_service.dart';

final lockServiceProvider = Provider<LockService>((ref) => LockService());

class LockState {
  /// The initial "is the lock on?" check has completed.
  final bool ready;

  /// The lock is configured and switched on.
  final bool enabled;

  /// Currently locked (must authenticate to proceed).
  final bool locked;

  const LockState({
    this.ready = false,
    this.enabled = false,
    this.locked = false,
  });

  LockState copyWith({bool? ready, bool? enabled, bool? locked}) => LockState(
        ready: ready ?? this.ready,
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
      );
}

class LockController extends StateNotifier<LockState> {
  final LockService _service;
  LockController(this._service) : super(const LockState()) {
    _init();
  }

  Future<void> _init() async {
    // Never block startup on the keystore: if it is slow or unavailable, treat
    // the lock as off so the app is always reachable.
    bool enabled;
    try {
      enabled = await _service
          .isEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      enabled = false;
    }
    state = LockState(ready: true, enabled: enabled, locked: enabled);
  }

  /// Mark the session as authenticated.
  void unlock() => state = state.copyWith(locked: false);

  /// Re-lock now (e.g. returning from background past the timeout).
  void lock() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  /// Re-read whether the lock is on (after enabling/disabling in Settings) and
  /// leave the app unlocked — the user is already authenticated in-session.
  Future<void> refresh() async {
    final enabled = await _service.isEnabled();
    state = state.copyWith(ready: true, enabled: enabled, locked: false);
  }
}

final lockControllerProvider =
    StateNotifierProvider<LockController, LockState>((ref) {
  return LockController(ref.watch(lockServiceProvider));
});
