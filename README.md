# Store Manager

An offline-first Flutter app for a small shop owner who distributes goods to
salespersons on credit. Implements the specification in [`CLAUDE.md`](CLAUDE.md).

Every balance, stock level, and total is **derived by summing the transaction
ledger** — there is no mutable balance stored anywhere (spec §2). The financial
rules (§6) are pure, unit-tested functions verified against the Appendix A
golden data.

## Architecture (three layers, §3)

```
lib/
  domain/         Pure Dart — no Flutter, no DB. The heart of the app.
    models.dart       Entities (Product, Salesperson, Txn, TxnLine, ...)
    period.dart       Month / quarter / all-time boundaries (§6.6)
    ledger.dart       All §6 derivations (stock, balance, cash, profit, ...)
    demo_data.dart    Realistic starter dataset, seeded on first run
    sample_data.dart  Appendix A fixture — used by tests / "reset to sample"
  data/           Drift (SQLite) — raw, append-only storage.
    database.dart     Tables + indexes (§4.2);  database.g.dart is generated
    repository.dart   Maps DB <-> domain, reactive ledger stream, all writes,
                      backup/restore, seeding, delete guards (§9)
  app/            Cross-cutting presentation infrastructure.
    providers.dart    Riverpod providers (ledger stream, money, period, ...)
    format.dart       Money (minor-unit integers) + date/qty formatting
    theme.dart        Design tokens (§15)
    ui.dart           Shared widgets (cards, sheets, dialogs)
  screens/        One file per screen (Home, Products, Sales, People,
                  Reports, Settings, Salesperson ledger).
  sheets/         Bottom-sheet forms (sale, return, payment, expense,
                  stock-in, product, salesperson, entry detail).
  services/       Receipt PDF (§10), CSV export (§11), backup/restore (§12).
```

## Verification

```
flutter test
```

29 tests, all green:

- `test/domain/appendix_a_test.dart` — reproduces **every Appendix A figure
  exactly** (stock, balances 6000/5600/2000, cash 65300, recognised profit
  3250/4000/840 → 8090, net 1890, ranking, low-stock) plus profit edge cases.
- `test/data/repository_test.dart` — acceptance criteria (§17) against a real
  in-memory SQLite DB: sale/return/payment/expense/stock-in effects,
  delete-restores-everything, delete/remove guards, backup round-trip.
- `test/app/dashboard_test.dart` — boots the **real app** and confirms the Home
  dashboard renders the Appendix A numbers.
- `test/app/navigation_smoke_test.dart` — pushed routes and a form sheet build
  at runtime.

## Build notes for this machine

This machine's Flutter SDK is **missing `gen_snapshot`**, so AOT compilation
fails. Two consequences:

- **Code generation must use JIT:**
  ```
  dart run build_runner build --force-jit
  ```
  (regenerate `lib/data/database.g.dart` after changing any Drift table.)
- `flutter test` and `flutter run` (debug) work normally (they use JIT).
  `flutter build` (release) and `dart compile exe` would need the missing
  `gen_snapshot`.

Otherwise this is a standard Flutter project: `flutter pub get`, then
`flutter run` on a connected Android/iOS device or emulator.
