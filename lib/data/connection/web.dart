import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web: SQLite compiled to WebAssembly, persisted via IndexedDB/OPFS.
/// Requires `web/sqlite3.wasm` and `web/drift_worker.dart.js` to be served.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'store_manager_v5',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    return result.resolvedExecutor;
  });
}
