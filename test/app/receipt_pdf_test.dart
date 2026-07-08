import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager/app/format.dart';
import 'package:store_manager/data/database.dart' hide Product, Salesperson;
import 'package:store_manager/data/repository.dart';
import 'package:store_manager/domain/models.dart';
import 'package:store_manager/services/receipt.dart';

/// Guards against the "blank receipt PDF on web" regression: the pdf package's
/// default standard fonts render blank in the browser, so the receipt must
/// embed a real TrueType font. A standard-font PDF carries no embedded font
/// program; verify the bytes contain one (FontFile2 = embedded TrueType).
void main() {
  // rootBundle asset loads (the Roboto fonts) need the binding initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sale receipt PDF embeds a TrueType font (not blank on web)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = StoreRepository(db);
    await repo.resetToSampleData();

    final ledger = await repo.loadLedger();
    final sale = ledger.txns.firstWhere((t) => t.type == TxnType.sale);
    const settings = StoreSettings();
    final money = Money(settings);

    final bytes = await buildReceiptPdf(ledger, sale, money, settings);

    expect(bytes.isNotEmpty, isTrue);
    // An embedded TrueType font program appears as a /FontFile2 stream.
    final text = String.fromCharCodes(bytes);
    expect(text.contains('FontFile2'), isTrue,
        reason: 'Receipt PDF must embed a TTF font or it renders blank on web');
  });
}
