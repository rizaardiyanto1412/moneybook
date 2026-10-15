#!/usr/bin/env bash
# One-shot Cloudflare deploy: creates the D1 database, sets the API token secret and deploys.
# Safe to re-run. Requires `npx wrangler login` first.
set -euo pipefail
cd "$(dirname "$0")/.."

npx wrangler whoami >/dev/null 2>&1 || { echo "Run: npx wrangler login"; exit 1; }

if grep -q "REPLACE_WITH_ID" wrangler.toml; then
  id=$(npx wrangler d1 list --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const db=JSON.parse(s).find(d=>d.name==="moneybook");console.log(db?db.uuid:"")})')
  if [ -z "$id" ]; then
    npx wrangler d1 create moneybook >/dev/null
    id=$(npx wrangler d1 list --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).find(d=>d.name==="moneybook").uuid))')
  fi
  sed -i.bak "s/REPLACE_WITH_ID_FROM_wrangler_d1_create/$id/" wrangler.toml && rm wrangler.toml.bak
  echo "D1 database: $id"
fi

token_file=.deploy-token
if [ ! -f "$token_file" ]; then
  openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-40 > "$token_file"
  chmod 600 "$token_file"
  npx wrangler secret put API_TOKEN < "$token_file"
fi

npm run build:web >/dev/null
url=$(npx wrangler deploy 2>&1 | tee /dev/stderr | grep -Eo 'https://[a-zA-Z0-9.-]+\.workers\.dev' | head -1)
token=$(cat "$token_file")
cat <<INFO

Deployed.
  App (open on iPhone Safari → Add to Home Screen): $url
  API token (also in server/$token_file):            $token
  MCP URL (claude.ai custom connector):             $url/mcp/$token
  Claude Code:  claude mcp add --transport http moneybook $url/mcp --header "Authorization: Bearer $token"
INFO
