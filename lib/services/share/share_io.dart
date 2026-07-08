import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native: write the bytes to a temp file and share it via the OS share sheet.
/// Returns true if the user did not dismiss the share sheet (i.e. the file was
/// most likely delivered), false if they cancelled.
Future<bool> shareBytes(
    Uint8List bytes, String filename, String mimeType) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  final result = await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
  return result.status != ShareResultStatus.dismissed;
}
