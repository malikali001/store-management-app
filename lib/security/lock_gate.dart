/// Wraps the app: shows the lock screen whenever the session is locked, and
/// re-locks after the configured idle time in the background. Also privacy-
/// obscures the UI while the app is inactive (task switcher).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import 'lock_controller.dart';
import 'lock_screen.dart';

/// Identifies the privacy overlay that hides the ledger in the OS app switcher,
/// so tests can assert it appears only when it should.
const privacyObscureKey = Key('privacy_obscure');

/// Shown while the initial "is the lock on?" check resolves, and on web for as
/// long as the app bundle is still loading.
///
/// Deliberately **static** — no spinner. A perpetual animation would stop
/// `pumpAndSettle` from ever settling in widget tests. But it must not be a bare
/// coloured box either: a featureless screen is indistinguishable from a crashed
/// one, and startup can take a while on a cold start (tens of seconds for a
/// debug web build). The name and mark make "starting" legible.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront, size: 44, color: AppColors.positive),
            SizedBox(height: 14),
            Text(
              'Store Manager',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Starting…',
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    final lock = ref.read(lockControllerProvider);

    // "Actually leaving the foreground", as opposed to a momentary loss of
    // focus. `inactive` is NOT included on purpose: it also fires while the user
    // is still looking at the app — another window takes focus, a permission
    // dialog opens, the notification shade is pulled down, a browser tab loses
    // focus — and obscuring then blanks the entire app in front of them.
    final leaving =
        st == AppLifecycleState.paused || st == AppLifecycleState.hidden;

    // The privacy screen hides the ledger in the OS app switcher. It is part of
    // the app lock, so it only applies when the lock is switched on — with no
    // PIN set there is nothing to protect, and blanking the UI would only ever
    // look like a crash.
    final obscure = lock.enabled && leaving;
    if (obscure != _obscured) setState(() => _obscured = obscure);

    if (!lock.enabled) return;
    if (leaving) {
      _backgroundedAt = DateTime.now();
    } else if (st == AppLifecycleState.resumed) {
      _maybeRelock();
    }
  }

  Future<void> _maybeRelock() async {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at == null) return;
    final minutes = await ref.read(lockServiceProvider).autoLockMinutes();
    final elapsed = DateTime.now().difference(at);
    if (elapsed >= Duration(minutes: minutes)) {
      ref.read(lockControllerProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockControllerProvider);

    // Until the initial check completes, show a neutral splash (avoids a flash
    // of the home screen before we know whether to lock).
    if (!lock.ready) return const _Splash();

    return Stack(
      children: [
        widget.child,
        if (lock.locked) const Positioned.fill(child: LockScreen()),
        if (_obscured && !lock.locked)
          const Positioned.fill(
            key: privacyObscureKey,
            child: ColoredBox(color: AppColors.background),
          ),
      ],
    );
  }
}
