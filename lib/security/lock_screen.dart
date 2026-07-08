/// Full-screen lock: biometric prompt (if enabled) plus a numeric PIN pad,
/// with brute-force cool-down feedback. Shown by [LockGate] while locked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../app/ui.dart';
import 'lock_controller.dart';
import 'lock_service.dart';
import 'recovery_sheets.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entry = '';
  String? _error;
  Duration _cooldown = Duration.zero;
  Timer? _ticker;
  bool _busy = false;

  static const _pinLength = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  LockService get _service => ref.read(lockServiceProvider);

  Future<void> _startup() async {
    await _refreshCooldown();
    if (await _service.isBiometricPreferred() &&
        await _service.biometricAvailable()) {
      _tryBiometric();
    }
  }

  Future<void> _refreshCooldown() async {
    final remaining = await _service.lockoutRemaining();
    if (!mounted) return;
    setState(() => _cooldown = remaining);
    _ticker?.cancel();
    if (remaining > Duration.zero) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
        final r = await _service.lockoutRemaining();
        if (!mounted) return;
        setState(() => _cooldown = r);
        if (r <= Duration.zero) _ticker?.cancel();
      });
    }
  }

  Future<void> _forgotPin() async {
    if (!await _service.hasRecoveryCode()) {
      if (!mounted) return;
      showError(context,
          'No recovery code was set. Use biometrics, or reinstall and restore from a backup.');
      return;
    }
    if (!mounted) return;
    await showForgotPinSheet(context, ref);
  }

  Future<void> _tryBiometric({bool explicit = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _service.authenticateBiometric();
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Only nag on an explicit tap; an auto-prompt that the user dismisses
      // should quietly fall back to the PIN pad.
      if (!ok && explicit) _error = 'Could not verify. Enter your PIN.';
    });
    if (ok) ref.read(lockControllerProvider.notifier).unlock();
  }

  Future<void> _onDigit(String d) async {
    if (_cooldown > Duration.zero || _entry.length >= _pinLength) return;
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == _pinLength) await _submit();
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    final pin = _entry;
    final result = await _service.verifyPin(pin);
    if (!mounted) return;
    switch (result) {
      case PinResult.ok:
        ref.read(lockControllerProvider.notifier).unlock();
        break;
      case PinResult.wrong:
        setState(() {
          _entry = '';
          _error = 'Wrong PIN. Try again.';
        });
        await _refreshCooldown();
        break;
      case PinResult.lockedOut:
        setState(() => _entry = '');
        await _refreshCooldown();
        break;
    }
  }

  String get _cooldownLabel {
    final s = _cooldown.inSeconds;
    if (s <= 0) return '';
    if (s < 60) return 'Too many attempts. Try again in ${s}s.';
    final m = (s / 60).ceil();
    return 'Too many attempts. Try again in ${m}m.';
  }

  @override
  Widget build(BuildContext context) {
    final lockedOut = _cooldown > Duration.zero;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 44, color: AppColors.positive),
                const SizedBox(height: 12),
                const Text('Enter your PIN',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                _Dots(filled: _entry.length, total: _pinLength),
                const SizedBox(height: 12),
                SizedBox(
                  height: 20,
                  child: Text(
                    lockedOut ? _cooldownLabel : (_error ?? ''),
                    style: TextStyle(color: AppColors.danger, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                _Pad(
                  onDigit: lockedOut ? null : _onDigit,
                  onBackspace: lockedOut ? null : _onBackspace,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: (_busy || lockedOut)
                      ? null
                      : () => _tryBiometric(explicit: true),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use biometrics'),
                ),
                TextButton(
                  onPressed: _busy ? null : _forgotPin,
                  child: const Text('Forgot PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int filled;
  final int total;
  const _Dots({required this.filled, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? AppColors.positive : Colors.transparent,
              border: Border.all(color: AppColors.positive, width: 1.5),
            ),
          ),
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  final void Function(String)? onDigit;
  final VoidCallback? onBackspace;
  const _Pad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 72,
          height: 64,
          child: child == null && onTap == null && label.isEmpty
              ? const SizedBox()
              : OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: AppColors.hairline),
                  ),
                  child: child ??
                      Text(label,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w500)),
                ),
        ),
      );
    }

    Widget row(List<Widget> children) =>
        Row(mainAxisAlignment: MainAxisAlignment.center, children: children);

    return Column(
      children: [
        for (final r in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          row([for (final d in r) key(d, onTap: () => onDigit?.call(d))]),
        row([
          key(''),
          key('0', onTap: () => onDigit?.call('0')),
          key('',
              onTap: onBackspace,
              child: const Icon(Icons.backspace_outlined)),
        ]),
      ],
    );
  }
}
