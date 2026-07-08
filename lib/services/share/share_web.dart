import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Web: share the bytes directly (no filesystem) via the Web Share API.
/// Returns true unless the user dismissed the share sheet.
Future<bool> shareBytes(
    Uint8List bytes, String filename, String mimeType) async {
  final result = await Share.shareXFiles(
      [XFile.fromData(bytes, name: filename, mimeType: mimeType)]);
  return result.status != ShareResultStatus.dismissed;
}
