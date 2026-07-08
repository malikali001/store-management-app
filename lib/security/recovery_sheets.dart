/// Recovery-code UI: the "save this code" sheet shown at setup / reset, and the
/// "Forgot PIN?" sheet that verifies the code and sets a new PIN.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../app/ui.dart';
import 'lock_controller.dart';
import 'lock_service.dart';

/// Show a generated recovery [code] for the user to save. Resolves to true once
/// they confirm they have saved it, or null if dismissed.
Future<bool?> showRecoveryCodeSheet(BuildContext context, String code) {
  return showAppSheet<bool>(context, _RecoveryCodeView(code: code));
}

/// "Forgot PIN?" flow: enter the recovery code and choose a new PIN. On success
/// the app is unlocked.
Future<void> showForgotPinSheet(BuildContext context, WidgetRef ref) {
  return showAppSheet<void>(context, const _ForgotPinSheet());
}

class _RecoveryCodeView extends StatelessWidget {
  final String code;
  const _RecoveryCodeView({required this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Your recovery code'),
        Text(
          'Write this down and keep it somewhere safe. If you forget your PIN, '
          'this code is the only way to reset it without losing your data. '
          'We cannot show it again — but you can generate a new one later.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: SelectableText(
            code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy code'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) showToast(context, 'Recovery code copied');
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('I have saved it'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ForgotPinSheet extends ConsumerStatefulWidget {
  const _ForgotPinSheet();
  @override
  ConsumerState<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends ConsumerState<_ForgotPinSheet> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (pin.length < 4) {
      setState(() => _error = 'New PIN must be at least 4 digits.');
      return;
    }
    if (pin != _confirm.text.trim()) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(lockServiceProvider)
        .resetPinWithRecovery(_code.text, pin);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case PinResult.ok:
        ref.read(lockControllerProvider.notifier).unlock();
        Navigator.pop(context);
        showToast(context, 'PIN reset. You are signed in.');
        break;
      case PinResult.wrong:
        setState(() => _error = 'That recovery code is not correct.');
        break;
      case PinResult.lockedOut:
        setState(() =>
            _error = 'Too many attempts. Please wait and try again.');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Reset your PIN'),
        Text(
          'Enter the recovery code you saved when you turned on the lock, then '
          'choose a new PIN.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Recovery code'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(labelText: 'New PIN'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(labelText: 'Confirm new PIN'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Reset PIN'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
