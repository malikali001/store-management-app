import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;

import '../app/format.dart';
import '../app/providers.dart';
import '../app/theme.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import 'backup_crypto.dart';
import 'backup_status.dart';
import 'share/share_bytes.dart';

/// Serialises the entire database to a single JSON file and shares it
/// (Section 12). Filename: store-backup-YYYY-MM-DD.json.
Future<void> backupToFile(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  try {
    final json = await repo.exportBackup();
    if (!context.mounted) return;
    // Optionally protect the shared file with a password.
    final password = await _promptSetBackupPassword(context);
    if (password == null) return; // cancelled
    final payload = password.isEmpty
        ? json
        : await encryptBackup(jsonEncode(json), password);
    final str = const JsonEncoder.withIndent('  ').convert(payload);
    final filename = 'store-backup-${todayIso()}.json';
    final shared = await shareBytes(
        Uint8List.fromList(utf8.encode(str)), filename, 'application/json');
    // Only record a successful off-device backup (drives the staleness nudge).
    // If the user dismissed the share sheet the data never left the device, so
    // we must keep nudging.
    if (shared) {
      await repo.setSetting(
          kLastBackupKey, '${DateTime.now().millisecondsSinceEpoch}');
    }
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not create the backup. Please try again.');
    }
  }
}

/// Picks a backup file, validates it, confirms, then replaces all local data
/// (Section 12).
Future<void> restoreFromFile(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);

  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not open the file picker.');
    }
    return;
  }
  if (picked == null || picked.files.isEmpty) return; // cancelled

  // Read file contents (prefer in-memory bytes, fall back to the path).
  String contents;
  try {
    final f = picked.files.first;
    if (f.bytes != null) {
      contents = utf8.decode(f.bytes!);
    } else {
      throw const FormatException('No file data');
    }
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not read the selected file.');
    }
    return;
  }

  Map<String, dynamic> decoded;
  try {
    final raw = jsonDecode(contents);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Not a backup object');
    }
    decoded = raw;
  } catch (e) {
    if (context.mounted) {
      showError(context, 'This file is not a valid backup.');
    }
    return;
  }

  // If the file is password-protected, ask for the password and decrypt.
  var data = decoded;
  if (isEncryptedBackup(decoded)) {
    if (!context.mounted) return;
    final pw = await _promptEnterBackupPassword(context);
    if (pw == null) return; // cancelled
    String innerStr;
    try {
      innerStr = await decryptBackup(decoded, pw);
    } on BackupPasswordError catch (e) {
      if (context.mounted) showError(context, e.message);
      return;
    }
    try {
      final inner = jsonDecode(innerStr);
      if (inner is! Map<String, dynamic>) {
        throw const FormatException('Not a backup object');
      }
      data = inner;
    } catch (_) {
      if (context.mounted) {
        showError(context, 'This backup could not be read after decrypting.');
      }
      return;
    }
  }

  if (!context.mounted) return;
  final ok = await confirm(
    context,
    title: 'Restore backup?',
    message:
        'This will replace all data on this device with the contents of the backup. This cannot be undone.',
    confirmLabel: 'Restore',
    danger: true,
  );
  if (!ok) return;

  try {
    await repo.restoreBackup(data);
    if (context.mounted) {
      showToast(context, 'Backup restored.');
    }
  } on DomainError catch (e) {
    if (context.mounted) {
      showError(context, e.message);
    }
  } catch (e) {
    if (context.mounted) {
      showError(context, 'Could not restore this backup.');
    }
  }
}

/// Ask whether to password-protect the backup. Returns null if cancelled, an
/// empty string for "no password", or the chosen password.
Future<String?> _promptSetBackupPassword(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _SetPasswordDialog(),
  );
}

/// Ask for the password needed to open an encrypted backup. Returns null if
/// cancelled, otherwise the entered text (which may be wrong — decryption
/// verifies it).
Future<String?> _promptEnterBackupPassword(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _EnterPasswordDialog(),
  );
}

class _SetPasswordDialog extends StatefulWidget {
  const _SetPasswordDialog();
  @override
  State<_SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<_SetPasswordDialog> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _pw.text;
    if (pw.isEmpty) {
      Navigator.pop(context, ''); // back up without a password
      return;
    }
    if (pw.length < 4) {
      setState(() => _error = 'Use at least 4 characters.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    Navigator.pop(context, pw);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Protect this backup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Set a password and anyone restoring this backup must enter it. '
            'Leave it blank to back up without a password.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: const InputDecoration(labelText: 'Password (optional)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            obscureText: true,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: const InputDecoration(labelText: 'Confirm password'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Back up')),
      ],
    );
  }
}

class _EnterPasswordDialog extends StatefulWidget {
  const _EnterPasswordDialog();
  @override
  State<_EnterPasswordDialog> createState() => _EnterPasswordDialogState();
}

class _EnterPasswordDialogState extends State<_EnterPasswordDialog> {
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter backup password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('This backup is password-protected.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: true,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => Navigator.pop(context, _pw.text),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _pw.text),
            child: const Text('Unlock')),
      ],
    );
  }
}
