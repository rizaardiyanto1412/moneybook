# Moneybook for iPhone (web app)

A home-screen web app (PWA) styled after Realbyte's Money Manager. Plain HTML, CSS and
ES modules: there is no build step. The server serves this folder as static files on the same
origin as the API (Cloudflare Workers static assets in production, `serveStatic` in
`server/src/node.ts` for self-hosting).

## Install on an iPhone

1. Deploy the server (`cd server && npm run deploy`) or run it on a machine your phone can
   reach (`API_TOKEN=... npm start`, then open `http://<host>:8787`). Use HTTPS in production:
   iOS only enables the service worker (offline shell) over HTTPS.
2. Open the URL in **Safari**.
3. Tap **Share**, then **Add to Home Screen**, then **Add**.
4. Open Moneybook from the home screen and enter your **API token** (the server's `API_TOKEN`
   secret, or the generated token in `DATA_DIR/token`). It is checked with `GET /api/settings` and
   stored in `localStorage` on the phone. **More › Log out** removes the token and cached data.

The first time you sign in, the app sets the server's time zone to the phone's if it is still
the default `UTC`.

## What's inside

```
index.html             shell, iOS meta tags, manifest and icon links
styles.css             all styles (light + dark via prefers-color-scheme)
manifest.webmanifest   PWA manifest
sw.js                  service worker: caches the app shell, never touches /api or /mcp
icons/                 apple-touch-icon (180), 192, 512, maskable 512
js/app.js              boot, login, tab bar, background sync loop
js/api.js              fetch wrapper (Bearer token, 401 → back to login)
js/store.js            local replica: /api/sync?since=cursor, localStorage cache, derived totals
js/format.js           Intl money/date helpers, month periods (month_start_day)
js/ui.js               page stack, bottom sheets, toast, icons
js/components.js       day-grouped transaction list, Income/Exp/Total strip
js/views/trans.js      Trans. tab: Daily / Calendar / Monthly / Summary, search
js/views/entry.js      add/edit form, account and category pickers, receipt upload
js/views/stats.js      Stats tab: donut + category list, category drill-down
js/views/accounts.js   Accounts tab and per-account ledger
js/views/more.js       settings, budgets, categories, accounts, log out
```

## Sync

The app keeps a full local copy of the data. It pulls `GET /api/sync?since=<cursor>` on launch,
when the app comes back to the foreground (`visibilitychange`), when the network returns, and
every 15 seconds while it's visible. Rows are upserted by id; tombstones (`deleted=1`) are
dropped. The cache lives in memory and in `localStorage` (`mb.cache.v1`), so the app opens
instantly and stays readable offline. Transactions added by your AI through MCP
(`source: "ai"`) show a ✨, flash once and trigger a toast.

Transactions created here are sent with `source: "web"`. Receipt photos are downscaled on a
canvas to at most 1600 px (JPEG, quality 0.85) before being uploaded to
`POST /api/transactions/:id/receipt`.

## Developing

```
cd server
API_TOKEN=dev DATA_DIR=/tmp/moneybook-dev PORT=8788 npx tsx src/node.ts
open http://localhost:8788        # token: dev
```

Edit files and reload. The service worker fetches the shell network-first, so changes show up
on the next load. Bump `VERSION` in `sw.js` when you add or rename files so the offline cache
is rebuilt.
