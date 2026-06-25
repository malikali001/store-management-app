import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../app/ui.dart';
import '../data/repository.dart';
import 'backup_status.dart';
import 'share/share_bytes.dart';

/// Serialises the entire database to a single JSON file and shares it
/// (Section 12). Filename: store-backup-YYYY-MM-DD.json.
Future<void> backupToFile(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  try {
    final json = await repo.exportBackup();
    final str = const JsonEncoder.withIndent('  ').convert(json);
    final filename = 'store-backup-${todayIso()}.json';
    await shareBytes(
        Uint8List.fromList(utf8.encode(str)), filename, 'application/json');
    // Record that an off-device backup was made (drives the staleness nudge).
    await repo.setSetting(
        kLastBackupKey, '${DateTime.now().millisecondsSinceEpoch}');
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
    await repo.restoreBackup(decoded);
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
