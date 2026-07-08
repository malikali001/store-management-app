/// Wraps the app: shows the lock screen whenever the session is locked, and
/// re-locks after the configured idle time in the background. Also privacy-
/// obscures the UI while the app is inactive (task switcher).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import 'lock_controller.dart';
import 'lock_screen.dart';

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
    // Obscure content in the app switcher while not in the foreground.
    final obscure = st != AppLifecycleState.resumed;
    if (obscure != _obscured) setState(() => _obscured = obscure);

    if (!lock.enabled) return;
    if (st == AppLifecycleState.paused || st == AppLifecycleState.hidden) {
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
    if (!lock.ready) {
      // Static splash (no perpetual animation) while the initial lock check
      // resolves — kept deliberately plain so it settles cleanly in tests.
      return const ColoredBox(color: AppColors.background);
    }

    return Stack(
      children: [
        widget.child,
        if (lock.locked) const Positioned.fill(child: LockScreen()),
        if (_obscured && !lock.locked)
          const Positioned.fill(
            child: ColoredBox(color: AppColors.background),
          ),
      ],
    );
  }
}
