# Moneybook for iPhone

A native SwiftUI client for the Moneybook server with the same Money Manager look as the web app
(`../web`): the date-labelled Trans. tab with Daily / Calendar / Weekly / Monthly / Summary, Stats /
Budget / Note with the labelled pie, Accounts, the Settings icon grid, and the entry form with its
docked black-header panel for account, category and the calculator keypad. Colours, sizes and layout
follow `web/styles.css`; the line icons are the web app's SVGs (`scripts/export-icons.mjs` copies them
into `Assets.xcassets/Icons`).

It signs in with your email and password (or the API token), keeps a local cache so it opens
instantly and works read-only offline, and syncs every 10 seconds while open, so expenses your AI
adds through MCP appear within seconds.

The data models, sync merge, periods, totals and money formatting come from `MoneybookCore`, and the
REST client from `MoneybookClient`, both in the Mac app's Swift package (`../mac`).

Requires iOS 18 or later and Xcode 27.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); it isn't checked in.

```sh
./scripts/generate.sh          # writes Moneybook.xcodeproj
open Moneybook.xcodeproj       # scheme: MoneybookiOS
```

`generate.sh` reads two settings from the environment:
- `BUNDLE_ID`, default `com.rizaardiyanto.moneybook`. Free Apple IDs need a bundle id no one else has registered.
- `DEVELOPMENT_TEAM`, your Apple team id; falls back to the contents of `~/.moneybook-ios-team`.

## Install on an iPhone

```sh
./scripts/install-device.sh    # Release build, signed with your team, installed with devicectl
```

The first time:
1. Sign in to Xcode with your Apple ID (Xcode → Settings → Accounts).
2. Connect the iPhone with a cable, unlock it and tap **Trust**.
3. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
4. After the first install, trust the developer under **Settings → General → VPN & Device Management**.

With a free Apple ID the app stops opening after 7 days; run `install-device.sh` again to renew it
(over Wi-Fi works once the phone has been paired). Your data lives on the server, so nothing is lost.

## Tests

`MoneybookUITests` walks the entry flow (category panel → keypad → note → Save) against a running
server. Point it at a throwaway one:

```sh
xcodebuild test -project Moneybook.xcodeproj -scheme MoneybookiOS \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' TEST_SERVER=http://127.0.0.1:8789 TEST_TOKEN=<token>
```

## Simulator

Debug builds accept launch arguments for testing without typing a password:
`-serverURL http://127.0.0.1:8787 -apiToken <token> -tab stats -transMode calendar -openEditor YES -panel amount -editLatest YES`.
