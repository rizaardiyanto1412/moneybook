# Moneybook for Mac

A native SwiftUI client for the Moneybook server, modelled on Realbyte's *Money Manager*:
Daily / Calendar / Monthly / Summary transactions, Stats with drill-down, Accounts with running
balances, Budgets, Settings and a menu bar extra with quick add. It is online-first with a local
cache, so it opens instantly and stays readable offline. Expenses your AI adds through MCP show up
within about 10 seconds, marked with a ✨.

Requires macOS 15 or later. Builds with the Command Line Tools alone; Xcode isn't needed.

## Build

```sh
cd mac
swift build                 # debug build
swift test                  # unit tests for sync merge, periods, aggregation, money (swift-testing)
./scripts/bundle.sh         # release build -> build/Moneybook.app (icon, Info.plist, ad-hoc signed)
open build/Moneybook.app
```

`bundle.sh` draws the icon with CoreGraphics (`scripts/make-icon.swift`), converts it with `sips` and
`iconutil`, writes `Info.plist` (bundle id `app.moneybook.mac`) and signs with `codesign -s -`.

### Notes on Command Line Tools-only builds
- The macOS 27 SDK declares SwiftUI's `@State` as a macro whose plugin ships only with Xcode, so the
  app uses `@UIState` (a typealias for the `SwiftUI.State` property wrapper) instead. `@Observable`,
  Swift Charts and `MenuBarExtra` work normally.
- The test target passes `-plugin-path …/host/plugins/testing` so the swift-testing macros resolve.

## Configure

Open **Settings** in the sidebar (or press ⌘,), enter the server URL and API token, click
**Test Connection**, then **Save**. The token is stored in the login Keychain; the URL is stored in
`UserDefaults`.

Headless or scripted setup:

```sh
defaults write app.moneybook.mac serverURL https://moneybook.example.workers.dev
defaults write app.moneybook.mac apiToken <token>   # moved into the Keychain on next launch
```

Debug builds (`swift build`, `swift run`) default to `http://localhost:8787` with token `dev`.
You can also pass `-serverURL <url> -apiToken <token>` on the command line (argument domain; not saved).

Server-side preferences (currency, month start day, week start, default account) live in
**Settings → Preferences** and sync to every client. On first connect, if the server's time zone is
still `UTC` and the Mac's isn't, the app sets it to the Mac's zone.

Ad-hoc signed builds have a new code signature after every rebuild, so macOS may ask once whether
the new build may read the Keychain item. Click **Always Allow**. The Keychain read happens off the
main thread, so the app still opens with cached data while the prompt is up.

## Local development server

```sh
cd server && API_TOKEN=dev DATA_DIR=/tmp/moneybook-dev PORT=8787 npx tsx src/node.ts &
cd mac && ./scripts/seed-dev.sh      # sample data for this and last month, budgets, an AI-added expense
```

## How sync works

- All rows live in memory and in `~/Library/Application Support/Moneybook/cache.json`.
- `GET /api/sync?since=<cursor>` runs on launch, whenever the app becomes active, every 10 s while
  it is active (every 60 s in the background, which keeps the menu bar fresh), and right after every
  write. Rows are upserted by id; tombstones (`deleted = 1`) are dropped; the cursor only moves forward.
- Writes go straight to the REST API. The returned row is applied immediately, then a sync follows.
  Offline, the cached data stays browsable; writes show an error.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘N / ⇧⌘I / ⇧⌘T | New expense / income / transfer |
| ⌘↩ / ⇧⌘↩ | Save / Save and continue (editor) |
| ⌘[ / ⌘] / ⌘T | Previous / next month (year in Monthly view) / today |
| ⌘1 … ⌘5 | Transactions, Stats, Accounts, Budget, Settings |
| ⌘R | Sync now |
| Return, double-click | Edit selected transaction |
| Delete | Delete selected transactions (asks first) |

Receipts: drop an image onto the editor, or click **Choose…**. Photos are re-encoded as JPEG (max
2400 px) and uploaded on save. Click a thumbnail to view it full size.

## Development aids

```sh
# Render every main screen (light, dark, editor sheets, menu bar) to PNGs, then quit.
# Works without Screen Recording permission, even when the display is locked.
build/Moneybook.app/Contents/MacOS/Moneybook -apiToken dev -snapshotDir /tmp/mb-shots

# Exercise every write path (transactions, receipts, budgets, categories, accounts, groups, settings)
# against the configured server, printing PASS/FAIL. Use a throwaway dev server.
.build/debug/Moneybook -apiToken dev -selfTest 1
```

## Layout

```
Sources/MoneybookCore/   models, Snapshot (sync merge + cache format), Periods, Ledger (aggregation), Money
Sources/Moneybook/       SwiftUI app: AppModel, APIClient, Keychain, views, menu bar, snapshot/self-test runners
Tests/MoneybookCoreTests swift-testing unit tests
scripts/                 bundle.sh, make-icon.swift, seed-dev.sh
```
