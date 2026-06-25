import 'package:drift/drift.dart';

/// Fallback used only when neither dart:io nor web is available. The real
/// implementations live in native.dart / web.dart and are chosen by the
/// conditional import in database.dart.
QueryExecutor openConnection() =>
    throw UnsupportedError('No database backend for this platform.');
