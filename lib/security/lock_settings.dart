/// Settings UI for the app lock (Section 7.12 "Data" area): turn the lock on
/// with a PIN, change the PIN, toggle biometric unlock, choose the auto-lock
/// delay, and turn the lock off (which requires the current PIN).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../app/ui.dart';
import 'lock_controller.dart';
import 'lock_service.dart';
import 'recovery_sheets.dart';

class LockSettingsSection extends ConsumerStatefulWidget {
  const LockSettingsSection({super.key});

  @override
  ConsumerState<LockSettingsSection> createState() =>
      _LockSettingsSectionState();
}

class _LockSettingsSectionState extends ConsumerState<LockSettingsSection> {
  bool _loading = true;
  bool _enabled = false;
  bool _biometricPreferred = false;
  bool _biometricAvailable = false;
  bool _hasRecovery = false;
  int _autoLockMinutes = 0;

  LockService get _service => ref.read(lockServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _service.isEnabled();
    final bioPref = await _service.isBiometricPreferred();
    final bioAvail = await _service.biometricAvailable();
    final hasRecovery = await _service.hasRecoveryCode();
    final mins = await _service.autoLockMinutes();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _biometricPreferred = bioPref;
      _biometricAvailable = bioAvail;
      _hasRecovery = hasRecovery;
      _autoLockMinutes = mins;
      _loading = false;
    });
  }

  Future<void> _turnOn() async {
    final pin = await _promptNewPin();
    if (pin == null) return;
    // Show a recovery code and require the user to confirm they saved it before
    // the lock is actually turned on — so they always have a way back in.
    final code = _service.generateRecoveryCode();
    if (!mounted) return;
    final saved = await showRecoveryCodeSheet(context, code);
    if (saved != true) return;
    await _service.setRecoveryCode(code);
    await _service.setPin(pin);
    await ref.read(lockControllerProvider.notifier).refresh();
    if (!mounted) return;
    showToast(context, 'App lock turned on');
    await _load();
  }

  Future<void> _resetRecovery() async {
    if (!await _confirmCurrentPin()) return;
    final code = _service.generateRecoveryCode();
    if (!mounted) return;
    final saved = await showRecoveryCodeSheet(context, code);
    if (saved != true) return;
    await _service.setRecoveryCode(code);
    if (!mounted) return;
    showToast(context, 'Recovery code updated');
    await _load();
  }

  Future<void> _changePin() async {
    // Require the current PIN before changing it.
    if (!await _confirmCurrentPin()) return;
    if (!mounted) return;
    final pin = await _promptNewPin();
    if (pin == null) return;
    await _service.setPin(pin);
    if (!mounted) return;
    showToast(context, 'PIN changed');
  }

  Future<void> _turnOff() async {
    if (!await _confirmCurrentPin()) return;
    await _service.disable();
    await ref.read(lockControllerProvider.notifier).refresh();
    if (!mounted) return;
    showToast(context, 'App lock turned off');
    await _load();
  }

  Future<void> _toggleBiometric(bool on) async {
    if (on && !_biometricAvailable) return;
    await _service.setBiometricPreferred(on);
    if (!mounted) return;
    setState(() => _biometricPreferred = on);
  }

  Future<void> _setAutoLock(int minutes) async {
    await _service.setAutoLockMinutes(minutes);
    if (!mounted) return;
    setState(() => _autoLockMinutes = minutes);
  }

  /// Returns true if the user re-enters the correct current PIN.
  Future<bool> _confirmCurrentPin() async {
    final pin = await showAppSheet<String>(context, const _PinEntrySheet(
      title: 'Enter current PIN',
    ));
    if (pin == null) return false;
    final result = await _service.verifyPin(pin);
    if (result == PinResult.ok) return true;
    if (!mounted) return false;
    showError(
        context,
        result == PinResult.lockedOut
            ? 'Too many attempts. Try again later.'
            : 'Wrong PIN.');
    return false;
  }

  Future<String?> _promptNewPin() {
    return showAppSheet<String>(context, const _NewPinSheet());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppCard(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.ink),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('App lock',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(_enabled ? 'On' : 'Off',
                  style: TextStyle(color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _enabled
                ? 'A PIN is required to open the app.'
                : 'Require a PIN (and optional fingerprint / Face) to open the app.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (!_enabled)
            FilledButton.icon(
              onPressed: _turnOn,
              icon: const Icon(Icons.lock),
              label: const Text('Turn on app lock'),
            )
          else ...[
            if (_biometricAvailable)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.positive,
                value: _biometricPreferred,
                onChanged: _toggleBiometric,
                title: const Text('Unlock with fingerprint / Face'),
              ),
            const SizedBox(height: 4),
            Text('Auto-lock', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final opt in const [
                  (0, 'Immediately'),
                  (1, 'After 1 min'),
                  (5, 'After 5 min'),
                ])
                  ChoiceChip(
                    label: Text(opt.$2),
                    selected: _autoLockMinutes == opt.$1,
                    onSelected: (_) => _setAutoLock(opt.$1),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.vpn_key_outlined, color: AppColors.ink),
              title: const Text('Recovery code'),
              subtitle: Text(
                _hasRecovery
                    ? 'Used to reset a forgotten PIN.'
                    : 'Not set — you could be locked out if you forget the PIN.',
                style: TextStyle(
                    color: _hasRecovery ? AppColors.muted : AppColors.warning,
                    fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: _resetRecovery,
                child: Text(_hasRecovery ? 'Reset' : 'Set up'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                    onPressed: _changePin, child: const Text('Change PIN')),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _turnOff,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Turn off'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-step "choose a new PIN" sheet; pops the confirmed PIN string.
class _NewPinSheet extends StatefulWidget {
  const _NewPinSheet();
  @override
  State<_NewPinSheet> createState() => _NewPinSheetState();
}

class _NewPinSheetState extends State<_NewPinSheet> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _first.text.trim();
    final b = _second.text.trim();
    if (a.length < 4) {
      setState(() => _error = 'Use at least 4 digits.');
      return;
    }
    if (a != b) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader('Choose a PIN'),
        _PinField(controller: _first, label: 'New PIN'),
        const SizedBox(height: 12),
        _PinField(controller: _second, label: 'Confirm PIN'),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: _submit, child: const Text('Save PIN')),
      ],
    );
  }
}

/// Single-PIN entry sheet (used to confirm the current PIN); pops the string.
class _PinEntrySheet extends StatefulWidget {
  final String title;
  const _PinEntrySheet({required this.title});
  @override
  State<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<_PinEntrySheet> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(widget.title),
        _PinField(controller: _c, label: 'PIN'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _PinField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: InputDecoration(labelText: label),
    );
  }
}
