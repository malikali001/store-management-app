import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:store_manager/app/providers.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/screens/settings_screen.dart';
import 'package:store_manager/services/backup_status.dart';

import 'lock_test_support.dart';

/// A fake file picker that always returns a preset JSON file, so the restore
/// flow can be driven end to end under `flutter test`.
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  final List<int> bytes;
  _FakeFilePicker(this.bytes);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      PlatformFile(
          name: 'store-backup.json',
          size: bytes.length,
          bytes: Uint8List.fromList(bytes)),
    ]);
  }
}

void main() {
  testWidgets('restore from a (fake-picked) backup file replaces the data',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Build a real backup from a seeded source database.
    final src = AppDatabase(NativeDatabase.memory());
    addTearDown(src.close);
    await StoreRepository(src).resetToSampleData();
    final backupJson = jsonEncode(await StoreRepository(src).exportBackup());
    FilePicker.platform = _FakeFilePicker(utf8.encode(backupJson));

    // A fresh, empty destination database.
    final dst = AppDatabase(NativeDatabase.memory());
    addTearDown(dst.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(dst),
        lockTestOverride(),
        backupStatusProvider.overrideWith(
            (ref) async => const BackupStatus(lastBackup: null, hasData: true)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    expect((await StoreRepository(dst).loadLedger()).products, isEmpty);

    await tester.ensureVisible(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();

    // Confirm the replace.
    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pumpAndSettle();

    final ledger = await StoreRepository(dst).loadLedger();
    expect(ledger.products, isNotEmpty);
    expect(ledger.salespersons, isNotEmpty);
  });

  testWidgets('restoring a malformed file is rejected', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    FilePicker.platform = _FakeFilePicker(utf8.encode('not a backup'));
    final dst = AppDatabase(NativeDatabase.memory());
    addTearDown(dst.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(dst),
        lockTestOverride(),
        backupStatusProvider.overrideWith(
            (ref) async => const BackupStatus(lastBackup: null, hasData: false)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    // No confirm dialog appears for an invalid file; an error is shown instead.
    expect(find.widgetWithText(FilledButton, 'Restore'), findsNothing);
  });
}
