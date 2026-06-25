# Backup & disaster recovery

The app is offline-first: all data lives in a local SQLite database on the
phone. That makes it fast and private, but it also means **a lost, stolen, or
replaced phone would lose the data** unless a copy exists somewhere else. This
document describes how the app protects against that today, and the plan for
fully-automatic cloud backup.

## What's implemented now

### 1. One-tap full backup → anywhere
`Settings → Back up everything` serialises the entire database (products,
salespersons, every transaction, lists, settings) to a single JSON file named
`store-backup-YYYY-MM-DD.json` and opens the OS share sheet. From there the
owner sends it to **Google Drive, WhatsApp, email, or any cloud app** — i.e.
off the device. That copy survives a lost phone.

### 2. Restore on a new phone
Install the app on the new/replacement phone, then
`Settings → Restore from backup`, pick the JSON file (from Drive/WhatsApp/etc.),
confirm, and all data is replaced exactly. Because every figure is derived from
the transaction ledger, a restored backup reproduces all balances, stock, and
profit identically (verified by `test/data/repository_test.dart`).

### 3. Backup reminder (anti-forgetting)
The app tracks when the last backup was made (`last_backup_at`). If there is
data and it has **never been backed up, or the last backup is older than 7
days**, a banner appears on launch — *"Your data is only on this phone. Back it
up…"* — with a **Back up now** button. `Settings → Data` also shows
*"Backed up N days ago"* (or a warning if stale). Logic is covered by
`test/app/production_test.dart`.

### 4. Safe by construction
- First run starts **empty** — no demo data to confuse a real owner.
- Destructive actions (Restore, Clear all data, Load demo) all require a
  confirm step.
- Restore validates the file shape before replacing anything; a malformed file
  is rejected with a clear message.

## Recommended habit for the shopkeeper
1. After a busy day, tap **Back up everything** and send the file to your own
   WhatsApp "saved messages" or Google Drive. It takes 5 seconds.
2. The weekly reminder will nag you if you forget.
3. If you change phones: install the app, **Restore from backup**, done.

## Planned: fully-automatic cloud backup (next step)
The remaining gap is that off-device backup is still a manual tap. The plan:

- **Google Drive auto-sync** using `google_sign_in` + `googleapis` (Drive
  `appDataFolder` scope, which is private to the app). On a schedule
  (e.g. daily + on app background) the app uploads the latest backup JSON and
  keeps the last N versions.
- A "Connected to Google Drive · last synced 2h ago" status in Settings.
- iCloud equivalent on iOS via a key-value/document container.

This is deferred because it requires (a) OAuth client credentials configured in
a Google Cloud project, and (b) testing on a real signed device build — neither
of which can be done in the current build environment. The manual backup +
restore + reminder loop above is complete and fully functional in the meantime,
and the JSON format is already the unit of sync, so adding Drive upload is
additive (no data-model changes).
