# Store Manager — Implementation Specification

> This document is the single source of truth for building the app. It is written to be read and implemented by an AI coding agent (Claude Code). Implement it section by section. Where this document gives an exact formula or number, treat it as a hard requirement and verify against the golden test data in Appendix A.

---

## 1. Purpose

A small shop owner buys products and distributes them to **salespersons**, who take goods **on credit**, sell them onward, and pay the owner back over time as they sell — then take more. There are no walk-in customers; **every sale goes through a salesperson**.

Today this is run on paper registers, which forces re-writing product names, manual arithmetic, and human error. This app replaces the registers with a phone app that is **offline, simple, and trustworthy**: the owner enters each product once, records movements with a few taps, and every balance, stock count, and profit figure is calculated automatically.

A fully working browser prototype already exists and defines the intended behaviour. This spec generalises it into a production mobile app.

## 2. Non-negotiable principles

1. **Offline-first.** The app must work fully with no internet connection. All data lives in a local database on the device. There is no server and no login.
2. **The ledger is the truth.** Every balance, stock level, and total is **derived by summing transactions** — never stored as an editable number. This is what guarantees the numbers always reconcile. Do not add a mutable `balance` column anywhere.
3. **Enter once, pick everywhere.** A product (and a salesperson) is typed once; everywhere else it is selected. No re-typing of names.
4. **Simple over clever.** Few screens, plain language, large tap targets. The user is a busy shopkeeper, possibly not tech-savvy. Favour clarity over features.
5. **Correct money.** The financial rules in Section 6 are exact. Implement them as pure, unit-tested functions before wiring any UI.

## 3. Recommended technology

Build a single cross-platform codebase for **Android and iOS**.

| Concern | Choice | Why |
|---|---|---|
| Framework | **Flutter (Dart)** | One codebase, compiles to native, excellent offline performance, mature. |
| Local database | **Drift** (SQLite, type-safe, reactive) | Reactive queries push DB changes straight to the UI, so derived totals refresh automatically. |
| State management | **Riverpod** | Simple, testable, plays well with Drift streams. |
| PDF receipts | `pdf` + `printing` | Generate and share/print receipts. |
| CSV export | `csv` + `share_plus` | Build sheets and share to any app. |
| Backup files | `path_provider`, `share_plus`, `file_picker` | Write/read JSON backup files. |
| Dates | Device-local time | See Section 6.6. |

> React Native + Expo + expo-sqlite is an acceptable alternative if Flutter is unavailable, but this spec assumes Flutter. Keep the **domain layer (Section 6) framework-independent** so it is portable regardless.

### Architecture (three layers)

- **Data layer** — Drift database, tables, and DAOs. Raw transactions only.
- **Domain layer** — pure Dart: entity models and the calculation functions in Section 6. No Flutter imports. Fully unit-tested against Appendix A. This is the heart of the app; build and test it first.
- **Presentation layer** — Riverpod providers expose derived values; Flutter widgets render them. No business math in widgets.

## 4. Data model

The store keeps a catalog (products, salespersons, lookup lists, settings) and an append-only **transaction ledger**. Everything else is computed from the ledger.

### 4.1 Money representation

Store all money as an **integer** in the smallest unit the shop uses. Add a setting `decimalPlaces` (default `0`). Display/parse using that setting and a configurable `currencySymbol`. Never use floating-point for stored amounts; round only at display. This avoids long-term rounding drift.

### 4.2 Tables

```
products
  id            TEXT PRIMARY KEY        -- uuid
  code          TEXT                    -- owner's SKU, optional, NOT unique (warn on dup)
  name          TEXT NOT NULL
  brand         TEXT                    -- references brands list (free text allowed)
  category      TEXT
  size          TEXT                    -- OPTIONAL: empty string when item has no size
  buy_price     INTEGER NOT NULL        -- current buy price (cost), minor units
  sell_price    INTEGER NOT NULL        -- current sell price (what salesperson owes), minor units
  archived      INTEGER NOT NULL DEFAULT 0
  created_at    INTEGER NOT NULL        -- epoch ms

salespersons
  id            TEXT PRIMARY KEY
  name          TEXT NOT NULL
  phone         TEXT
  opening       INTEGER NOT NULL DEFAULT 0   -- amount already owed at start, minor units
  opening_margin_bp INTEGER NOT NULL DEFAULT 0 -- margin on opening balance in basis points (0 = no profit). Optional.
  archived      INTEGER NOT NULL DEFAULT 0
  created_at    INTEGER NOT NULL

transactions
  id            TEXT PRIMARY KEY
  type          TEXT NOT NULL           -- 'stockin' | 'sale' | 'return' | 'payment' | 'expense'
  date          TEXT NOT NULL           -- 'YYYY-MM-DD', local date
  created_at    INTEGER NOT NULL        -- epoch ms, tiebreaker for same-date ordering
  salesperson_id TEXT                   -- sale | return | payment
  product_id    TEXT                    -- stockin only
  qty           INTEGER                 -- stockin only
  unit_buy      INTEGER                 -- stockin: buy price at the time (snapshot)
  amount        INTEGER                 -- payment | expense
  category      TEXT                    -- expense
  recurring     INTEGER DEFAULT 0       -- expense: tagged monthly (see 9.5)
  note          TEXT

transaction_lines                       -- for sale | return only
  id            TEXT PRIMARY KEY
  transaction_id TEXT NOT NULL
  product_id    TEXT NOT NULL
  qty           INTEGER NOT NULL
  unit_sell     INTEGER NOT NULL        -- sell price snapshot at the moment of the transaction
  unit_buy      INTEGER NOT NULL        -- buy price snapshot (cost basis for profit)

lists                                    -- managed dropdown values
  kind          TEXT NOT NULL           -- 'category' | 'brand' | 'size' | 'expense_category'
  value         TEXT NOT NULL
  PRIMARY KEY (kind, value)

settings
  key           TEXT PRIMARY KEY        -- 'store_name','currency','opening_cash','low_stock','decimal_places'
  value         TEXT NOT NULL
```

**Price snapshots are mandatory.** When a sale/return/stock-in is created, copy the product's current `buy`/`sell` into the line/row. Editing a product's price later must not change historical transactions. Returns reverse at the price the goods left at — use the line's snapshot.

## 5. Transactions — the five movements

Each is one row (plus lines for sale/return). All effects below are **computed**, never written as stored balances.

| Type | Fields | Effect on stock | Effect on owed | Effect on cash | Notes |
|---|---|---|---|---|---|
| **Stock in** | product, qty, unit_buy, date | + qty to that product | — | − qty×unit_buy | Owner buys goods. |
| **Sale** | salesperson, date, lines[] | − each line qty | + Σ(qty×unit_sell) | — | Produces a PDF receipt. |
| **Return** | salesperson, date, lines[] | + each line qty | − Σ(qty×unit_sell) | — | Unsold goods come back. |
| **Payment** | salesperson, amount, date | — | − amount | + amount | Recognises profit (6.5). |
| **Expense** | category, amount, date, recurring | — | — | − amount | Overheads only — NOT buying stock. |

> Buying stock is **Stock in**, never an Expense. Keep them separate so profit is true (cost of goods vs overheads).

## 6. Business rules and formulas (exact)

Implement these as pure functions over the ledger. They must reproduce Appendix A exactly. For performance, the production app may compute them with SQL aggregates, but the SQL must return identical results to these definitions.

### 6.1 Product stock
```
stock(P) = Σ stockin.qty   where product_id = P
         + Σ line.qty       where line.product_id = P AND parent.type = 'return'
         − Σ line.qty       where line.product_id = P AND parent.type = 'sale'
```

### 6.2 Salesperson "goods taken" (sell and cost basis)
```
sellTaken(S) = Σ saleLineSell(S) − Σ returnLineSell(S)     // using unit_sell snapshots
costTaken(S) = Σ saleLineBuy(S)  − Σ returnLineBuy(S)      // using unit_buy snapshots
```

### 6.3 Salesperson balance (what they owe you)
```
balance(S) = opening(S) + sellTaken(S) − Σ payment.amount(S)
```

### 6.4 Store-wide money
```
cashOnHand   = openingCash
             + Σ payment.amount
             − Σ (stockin.qty × stockin.unit_buy)
             − Σ expense.amount

stockValue   = Σ over products of  max(0, stock(P)) × buy_price(P)   // money sitting as goods, at current cost
totalOwed    = Σ over salespersons of balance(S)
```

### 6.5 Profit — cash-basis, proportional (THE key rule)

Profit is recognised **only when money is actually received**, and each payment is split into "cost coming back" and "profit", in proportion to that salesperson's blended margin. Profit is a **derived value** (recomputed, never trusted from a stale store).

For a salesperson `S`, compute per-payment profit by walking their events in chronological order (`date`, then `created_at`):

```
cumSell = opening(S)
cumCost = opening(S) − opening(S) × opening_margin_bp / 10000   // opening defaults to 0 margin → cumCost = cumSell
recognised = 0
for each event of S in chronological order:
    if sale:    cumSell += saleSell;  cumCost += saleCost
    if return:  cumSell -= retSell;   cumCost -= retCost
    if payment(amount A):
        marginPool = (cumSell − cumCost) − recognised        // profit not yet recognised
        ratio      = cumSell > 0 ? (cumSell − cumCost) / cumSell : 0
        p          = round(A × ratio)
        p          = clamp(p, 0, max(0, marginPool))          // never overstate; never negative
        recognised += p
        assign p to this payment
```

Then:
```
profit(period) = Σ (perPayment profit, for payments dated in period)
               − Σ (expense.amount, for expenses dated in period)
```

Properties this guarantees: total recognised profit for a salesperson can never exceed their actual margin earned (`sellTaken − costTaken`); it ties out exactly once they have paid for everything; and because they never fully settle, profit accrues smoothly as money arrives rather than waiting for a zero balance.

### 6.6 Periods
```
thisMonth   = [first day of current month (local), today]
thisQuarter = [first day of current calendar quarter (local), today]
allTime     = unbounded
```
Use the **device-local** date for "today" and for month/quarter boundaries. Store transaction dates as local `YYYY-MM-DD`. A transaction is "in period" if `from ≤ date ≤ to`.

### 6.7 Rankings and alerts
```
takenInPeriod(S) = Σ saleLineSell(S) − Σ returnLineSell(S)  for transactions dated in period
topSalespersons  = salespersons sorted by takenInPeriod desc, excluding zero
lowStock         = products where stock(P) ≤ settings.low_stock (default 20)
```

## 7. Screens and navigation

Bottom tab bar with five tabs: **Home · Products · Sales · People · Reports**. Settings is reached from a gear icon on Home. Forms open as bottom sheets. Confirmations and entry details open as bottom sheets.

### 7.1 Home (dashboard)
- A period selector: Month / Quarter / All time (affects Profit and the ranking).
- Four metric cards: **Cash on hand**, **Stock value**, **Owed to you**, **Profit · {period}**. Negative cash/profit shown in the danger colour.
- Two small chips: **Expenses · {period}** and **Low stock · N items**.
- Four quick actions: New sale, Stock in, Record payment, Expense.
- **Top salespersons** list for the period (name, amount owed, amount taken). Tap → that person's ledger.
- Gear icon → Settings.

### 7.2 Products
- Search box (matches name, brand, code, category).
- "Add" button → product form.
- Products **grouped by brand + name**; each size is a row showing the size label (or "Item" when no size), code, sell price, current stock, and a "low" badge when at/under threshold.
- Tap a row → **Product actions** sheet: shows current stock and sell price, with buttons **Add stock** and **Edit details**, plus a short **Recent stock added** list (tap an entry to view/delete it).

### 7.3 Product form (add/edit)
Fields: code (optional), size (optional, with suggestions from the sizes list), name (required), brand (suggestions), category (suggestions), buy price, sell price. Brand/category/size typed here are added to their lists automatically. Edit screen also offers **Delete** — but deletion is **blocked if the product appears in any transaction** (Section 11); offer **Archive** instead (hides from lists, keeps history).

### 7.4 Sales & payments
- Three actions: **New sale**, **Record payment**, **Return goods**.
- List of recent sales and returns (newest first): salesperson, date, piece count, amount. Returns flagged and shown as a credit. Tap a sale → its receipt; tap a return → its entry sheet.

### 7.5 New sale (sheet)
- Pick salesperson.
- Add line items: pick product (shows available stock), enter qty; unit sell auto-fills from the product (still editable). Running total updates live. Block adding more than available stock (accounting for lines already added in this sale).
- Date (defaults today). Save → store sale, then open the **receipt** with a Download/Share PDF action.

### 7.6 Return goods (sheet)
Same shape as a sale; saving credits the salesperson's balance and returns the goods to stock. Warn (but allow) if a return quantity exceeds what the salesperson has net taken of that product.

### 7.7 Record payment (sheet)
- Pick salesperson (show current balance). Enter amount, date. Warn (but allow) if amount exceeds balance (creates a credit). Save → balance drops, cash rises, profit recognised per 6.5. Toast the new balance.

### 7.8 Expense (sheet)
Category (suggestions), amount, date, optional note, and a **"Mark as monthly recurring"** toggle (see 9.5). Save → reduces cash and profit for the period.

### 7.9 People
List of salespersons sorted by balance (highest owed first): name, balance. Header "Add" → add-person form (name, optional phone, optional opening balance, optional opening margin). Tap → ledger.

### 7.10 Salesperson ledger
- Big current balance owed.
- Buttons: Record payment, New sale.
- Full history newest-first: "Took goods" (+), "Returned goods" (−), "Payment received" (−). Tap a sale → receipt; tap any entry → entry sheet (with delete).
- At the bottom: **Remove salesperson** — allowed only when balance is settled (≈0); otherwise show why. Removing keeps historical records intact; any orphaned references display as "(former salesperson)".

### 7.11 Reports
- Period selector.
- **Money · {period}**: goods taken, goods returned, money collected, recognised (gross) profit, expenses, **net profit**.
- **Expenses by category** for the period.
- **Recent expenses** list (tap to view/delete).
- **Who sells more**: salespersons ranked by goods taken in the period.
- **Export**: download Products / Salespersons / Transactions as CSV (Section 13).

### 7.12 Settings
Store name, currency symbol, decimal places, opening cash, low-stock threshold. Manage lists (categories, brands, expense categories): view chips, add, remove. **Backup everything** (file), **Restore from backup**, **Reset to sample data**.

## 8. Entry detail & the "undo" model

There is no in-place edit in v1. The correction model is **delete-and-re-add**: tapping any transaction opens an entry detail sheet with a **Delete this entry** button (with a confirm step). Because all balances are derived, deleting a transaction recalculates every figure correctly and instantly. Provide this for all five transaction types (sales via the receipt sheet; others via the entry sheet). A proper edit screen is a v1.1 enhancement and, if added, must be implemented as an atomic delete+create so the derivation stays consistent.

## 9. Edge cases, validations, and their solutions

1. **Selling more than stock** — block in the new-sale form; show available quantity (net of lines already added in the current sale).
2. **Deleting a product with history** — block; offer Archive (sets `archived=1`, hidden from pickers/lists, history preserved). Guard every product lookup so a missing product renders as "(deleted product)" rather than crashing.
3. **Removing a salesperson** — allow only when balance ≈ 0. Guard salesperson lookups to "(former salesperson)" for any orphaned history.
4. **Overpayment / over-return** — allow, but warn first ("more than they owe" / "more than they took"). Balances may legitimately go negative (a credit).
5. **Recurring expenses** — the toggle only **tags** the expense. On the first launch of a new month, show a sheet listing tagged recurring expenses and let the user tap once to add this month's copies. **Never auto-post silently.**
6. **Profit on edits** — profit is fully derived (6.5), so deleting/adding a sale, return, or payment automatically and correctly re-splits all of that salesperson's payment profits. No stored profit to drift.
7. **Opening balance margin** — defaults to 0 (repaying it is pure cost recovery). The optional `opening_margin_bp` lets the owner assign a margin if known.
8. **Duplicate product code** — allowed but warn on save if the code already exists.
9. **Backup file validity** — on restore, validate the JSON shape (has products, salespersons, transactions, settings) before replacing data; reject and explain if malformed.
10. **Large data** — keep derivations efficient (indexed columns: `transactions(type)`, `transactions(salesperson_id)`, `transactions(date)`, `transaction_lines(product_id)`, `transaction_lines(transaction_id)`). Prefer SQL aggregates over loading all rows once data grows.
11. **Time zones / back-dating** — order events by `date` then `created_at`; this makes profit and receipt "previous balance" deterministic even for back-dated entries.

## 10. Receipt (PDF)

Generated for each sale; shareable and printable.

Contents, top to bottom: store name; "Sale receipt", short receipt number (first 6 chars of id, uppercased), date; salesperson name; a table of line items (product · size, quantity, unit sell price, line total); the **sale total**; then **previous balance**, **this sale (+)**, **new balance owed**. **Never show buy price or cost.**

"Previous balance" = the salesperson's balance from all their transactions strictly before this sale (by `date`, then `created_at`); "new balance owed" = previous + this sale total.

## 11. Export (CSV)

- **Products**: code, name, brand, category, size, buy, sell, current stock.
- **Salespersons**: name, goods taken (incl. opening), paid, owed, profit recognised.
- **Transactions**: date, type, salesperson, detail, money-in, money-out. Guard deleted product/salesperson names.

Generate with proper CSV escaping; share via the OS share sheet.

## 12. Backup & restore

- **Manual backup**: serialise the entire database (all tables + settings) to a single JSON file and share it (Drive, email, WhatsApp, etc.). Filename: `store-backup-YYYY-MM-DD.json`.
- **Restore**: pick a backup file, validate, then replace all local data and refresh.
- **Automatic backup (build in v1 if feasible, else v1.1)**: a weekly background export to the user's Google Drive, plus a "last backed up N days ago" indicator on Settings and a nudge if it's stale. This addresses the single-device data-loss risk; manual backup remains available regardless.
- Multi-device sync is **out of scope for v1** (single owner, single device).

## 13. Settings & configuration

Persist in the `settings` table: `store_name` (default "My Store"), `currency` (default empty), `decimal_places` (default 0), `opening_cash` (minor units), `low_stock` (default 20). All are editable; changing them re-derives displayed values immediately.

## 14. Non-functional requirements

- **Offline**: zero network dependency for any core function.
- **Reliability**: every write is a single DB transaction; derived values come straight from the DB. No data is ever held only in memory.
- **Performance**: dashboard and lists must render quickly with 10,000+ transactions (use indexed SQL aggregates).
- **Reactivity**: a change in one screen (e.g. a payment) updates Home totals without a manual refresh (Drift streams → Riverpod).
- **Accessibility**: large tap targets (≥44px), readable type, supports the OS text-scaling, visible focus.
- **Localisation**: currency symbol and decimal places configurable; format numbers with grouping separators.
- **Resilience**: wrap PDF/CSV/file operations in error handling with plain-language messages; never crash on a missing referenced product or salesperson.

## 15. Visual design

Calm, clean, ledger-like. Light theme.

| Token | Value |
|---|---|
| App background | `#EEF0ED` |
| Surface / cards | `#FFFFFF` |
| Ink (text) | `#1C211F` |
| Muted text | `#6C726F` |
| Hairline / border | `#E4E7E4` |
| Primary / positive (money in, profit) | `#157A5E` |
| Danger / money out / owed | `#B04A2E` |
| Warning / low stock | `#9A6A0C` |

- System humanist sans typeface; two weights (regular 400, medium ~500/600 for emphasis). Sentence case everywhere.
- Money uses **tabular figures** so columns align. Round on display per `decimal_places`.
- Cards: 14px radius, 0.5–1px hairline border, subtle or no shadow.
- Generous spacing; minimal decoration. The signature is aligned numbers and instant recalculation, not ornament.

The existing browser prototype is the visual and behavioural reference — match its layout and wording.

## 16. Build plan (milestones)

1. **Domain core** — entities + all Section 6 functions in pure Dart. Unit-test against Appendix A until every number matches. *(Do this first; nothing else proceeds until these pass.)*
2. **Data layer** — Drift tables, DAOs, reactive queries; seed with Appendix A sample data on first run.
3. **Catalog** — Products (list/group/search/add/edit/archive), salespersons (list/add), settings, managed lists.
4. **Movements** — Stock in, New sale (+ stock validation), Return, Payment (+ profit), Expense; entry-delete model.
5. **Dashboard & Reports** — metric cards, period selector, rankings, expenses breakdown.
6. **Receipts & exports** — PDF receipt, CSV exports.
7. **Backup/restore** — manual JSON backup/restore; recurring-expense month-start confirm; then automatic Drive backup.
8. **Polish** — empty states, warnings (overpay/over-return/dup code), accessibility, performance pass.

## 17. Acceptance criteria

- All Appendix A numbers reproduced exactly by the domain layer (and by the running app's dashboard).
- Recording a sale reduces stock and raises owed; a payment raises cash, lowers owed, and recognises profit per 6.5; a return restores stock and lowers owed; an expense lowers cash and profit; stock-in raises stock and lowers cash.
- Deleting any transaction returns every figure to what it was before that transaction.
- A sale produces a correct PDF receipt with previous/this/new balance and no buy price.
- The app functions with the device in airplane mode throughout.
- Backup then restore on a fresh install reproduces all data exactly.

---

## Appendix A — Golden sample data and expected results

Seed the app with this on first run, and use it as the unit-test fixture. Currency symbol empty, decimal places 0, opening cash 150000, low-stock threshold 20. Treat all dates as within the current month.

**Products** (code, name, brand, category, size, buy, sell):
```
TS-M , Cotton tee , Acme , T-shirts , M   , 180 , 250
TS-L , Cotton tee , Acme , T-shirts , L   , 180 , 250
TS-XL, Cotton tee , Acme , T-shirts , XL  , 190 , 270
SH-7 , Runner shoe, Nova , Footwear , 7   , 900 , 1200
SH-8 , Runner shoe, Nova , Footwear , 8   , 900 , 1200
CP-S , Logo cap   , Acme , Caps     , Std , 90  , 150
```

**Salespersons**: Rahul, Amir, Sana (all opening 0).

**Stock in**: TS-M ×100@180, TS-L ×80@180, TS-XL ×40@190, SH-7 ×30@900, SH-8 ×25@900, CP-S ×200@90.

**Sales**: Rahul [TS-M ×40, CP-S ×50]; Amir [SH-7 ×10, SH-8 ×8]; Sana [TS-L ×20].

**Return**: Rahul [CP-S ×10].

**Payments**: Rahul 10000; Amir 16000; Sana 3000.

**Expenses**: Rent 3000, Transport 1200, Labour 2000.

**Expected results:**

| Quantity | Expected |
|---|---|
| Stock — TS-M / TS-L / TS-XL | 60 / 60 / 40 |
| Stock — SH-7 / SH-8 / CP-S | 20 / 17 / 160 |
| Stock value | 76900 |
| Balance — Rahul / Amir / Sana | 6000 / 5600 / 2000 |
| Total owed | 13600 |
| Cash on hand | 65300 |
| Recognised profit — Rahul / Amir / Sana | 3250 / 4000 / 840 |
| Recognised profit — total | 8090 |
| Expenses (this month) | 6200 |
| Net profit (this month) | 1890 |
| Low-stock items (≤20) | 2 (SH-7, SH-8) |
| Ranking by goods taken | Amir 21600, Rahul 16000, Sana 5000 |

Profit detail for verification (per 6.5, all sales precede payments so the blended ratio applies): Rahul margin ratio = (16000−10800)/16000 = 0.325 → 10000×0.325 = 3250; Amir = (21600−16200)/21600 = 0.25 → 16000×0.25 = 4000; Sana = (5000−3600)/5000 = 0.28 → 3000×0.28 = 840.

## Appendix B — Glossary

- **Salesperson** — a distributor who takes goods on credit and pays as they sell. The only kind of customer.
- **Owed / balance** — money a salesperson currently owes the owner (at sell price).
- **Goods taken** — total sell-value of goods a salesperson has received, net of returns.
- **Stock value** — current inventory valued at buy (cost) price.
- **Cash on hand** — actual money the owner holds.
- **Recognised profit** — margin counted as earned, only as payments arrive (cash-basis), split proportionally.
- **Expense** — an overhead (rent, transport, labour, bills). Buying stock is not an expense.
