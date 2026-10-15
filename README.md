# Moneybook

A personal clone of Realbyte's Money Manager: a native Mac app, an iPhone home-screen web app, a REST API,
and an MCP server so your AI can log expenses ("I spent $12 on lunch") and they show up in the apps.

```
server/   API + MCP (TypeScript/Hono). Runs on Cloudflare Workers + D1 (free) or any VPS (Node + SQLite).
web/      iPhone web app (PWA), served by the server.
mac/      Native macOS SwiftUI app (builds with Command Line Tools, no Xcode).
ios/      Native iPhone SwiftUI app (Xcode + XcodeGen); shares mac/'s MoneybookCore and MoneybookClient.
docs/     API.md (REST API reference).
```

## Deploy (Cloudflare, free)
```
cd server && npm install
npx wrangler login
./scripts/deploy-cloudflare.sh     # prints app URL, API token and MCP URL
```

## Self-host (VPS)
```
echo "API_TOKEN=$(openssl rand -hex 20)" > .env
docker compose up -d               # http://your-vps:8787 (put it behind HTTPS, e.g. Caddy)
```

## Connect your AI (MCP)
- **Claude Code:** `claude mcp add --transport http moneybook https://<host>/mcp --header "Authorization: Bearer <token>"`
- **Claude Desktop / claude.ai / Claude iPhone app:** Settings → Connectors → Add custom connector → URL `https://<host>/mcp/<token>`
- Any other MCP client that supports Streamable HTTP works the same way.

Then just say: *"Log $8.50 coffee at Blue Bottle on my card"*, *"How much did I spend on food this month?"*,
or send a receipt photo and say *"add this"*.

## Import from Money Manager
In Money Manager: More → Backup → Export to a file. Then in Moneybook: **Settings → Backup → Import from Money Manager**
and pick the `.mmbak`. It's read in the browser, previewed (counts, currency) and uploaded; choose *Replace everything* or *Add to existing*.

Or from the command line:
```
cd server
npx tsx scripts/import-mmbak.ts "MM(...).mmbak" --dry-run                                  # preview counts
npx tsx scripts/import-mmbak.ts "MM(...).mmbak" --url https://<host> --token <token> --replace
```
`--replace` swaps out the starter accounts and categories. Re-running is safe, because rows keep their Money Manager ids.
Android backups follow the reverse-engineered schema exactly. iPhone backups are mapped best-effort; if a column is missing,
the importer says so, and `--inspect` prints the backup's tables. Photos aren't stored inside `.mmbak` files.

## Local dev
```
cd server && API_TOKEN=dev npm start      # http://localhost:8787
npm test
```
