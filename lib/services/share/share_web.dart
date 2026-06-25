import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Web: share the bytes directly (no filesystem) via the Web Share API.
Future<void> shareBytes(
    Uint8List bytes, String filename, String mimeType) async {
  await Share.shareXFiles(
      [XFile.fromData(bytes, name: filename, mimeType: mimeType)]);
}
