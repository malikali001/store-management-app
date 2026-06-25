import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Settings key holding the epoch-ms of the last successful off-device backup.
const kLastBackupKey = 'last_backup_at';

/// How long before a backup is considered stale and the owner is nudged.
const kBackupStaleAfter = Duration(days: 7);

class BackupStatus {
  final DateTime? lastBackup;
  final bool hasData; // anything worth losing?
  const BackupStatus({required this.lastBackup, required this.hasData});

  /// Stale if there is data and it has never been backed up, or the last
  /// backup is older than [kBackupStaleAfter].
  bool get isStale {
    if (!hasData) return false;
    final t = lastBackup;
    if (t == null) return true;
    return DateTime.now().difference(t) > kBackupStaleAfter;
  }

  String get humanLabel {
    final t = lastBackup;
    if (t == null) return 'Never backed up';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Backed up just now';
    if (d.inHours < 1) return 'Backed up ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'Backed up ${d.inHours} h ago';
    if (d.inDays == 1) return 'Backed up yesterday';
    return 'Backed up ${d.inDays} days ago';
  }
}

/// Reactive backup status — recomputed whenever the ledger changes.
final backupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final ledger = ref.watch(ledgerProvider).valueOrNull;
  final repo = ref.read(repositoryProvider);
  final raw = await repo.rawSetting(kLastBackupKey);
  final ms = int.tryParse(raw ?? '');
  final hasData = ledger != null &&
      (ledger.products.isNotEmpty ||
          ledger.salespersons.isNotEmpty ||
          ledger.txns.isNotEmpty);
  return BackupStatus(
    lastBackup: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    hasData: hasData,
  );
});
