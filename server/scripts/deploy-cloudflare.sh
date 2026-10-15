#!/usr/bin/env bash
# One-shot Cloudflare deploy: deploys the Worker (creating its D1 database the first time),
# sets the API token secret and prints how to sign in. Safe to re-run. Requires `npx wrangler login` first.
set -euo pipefail
cd "$(dirname "$0")/.."

npx wrangler whoami >/dev/null 2>&1 || { echo "Run: npx wrangler login"; exit 1; }

npm run build:web >/dev/null
url=$(npx wrangler deploy -c ../wrangler.toml 2>&1 | tee /dev/stderr | grep -Eo 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -1)

token_file=.deploy-token
if [ ! -f "$token_file" ]; then
  openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-40 > "$token_file"
  chmod 600 "$token_file"
  npx wrangler secret put API_TOKEN -c ../wrangler.toml < "$token_file"
fi
token=$(cat "$token_file")
cat <<INFO

Deployed.
  App (open on iPhone Safari → Add to Home Screen): $url
  API token (also in server/$token_file):            $token
  MCP URL (claude.ai custom connector):             $url/mcp/$token
  Claude Code:  claude mcp add --transport http moneybook $url/mcp --header "Authorization: Bearer $token"
INFO
