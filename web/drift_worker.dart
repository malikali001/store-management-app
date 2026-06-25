// Compiled to web/drift_worker.dart.js with:
//   dart compile js web/drift_worker.dart -o web/drift_worker.dart.js -O2
// Drift's WasmDatabase runs SQLite in this dedicated/shared worker.
import 'package:drift/wasm.dart';

void main() {
  WasmDatabase.workerMainForOpen();
}
