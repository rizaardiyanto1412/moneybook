#!/bin/sh
# Regenerates Moneybook.xcodeproj from project.yml.
#   BUNDLE_ID         defaults to com.rizaardiyanto.moneybook (must be unique per Apple team)
#   DEVELOPMENT_TEAM  your Apple team id; read from ~/.moneybook-ios-team if unset
set -e
cd "$(dirname "$0")/.."
export BUNDLE_ID="${BUNDLE_ID:-com.rizaardiyanto.moneybook}"
if [ -z "$DEVELOPMENT_TEAM" ] && [ -f "$HOME/.moneybook-ios-team" ]; then
  DEVELOPMENT_TEAM="$(cat "$HOME/.moneybook-ios-team")"
fi
export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
xcodegen generate --quiet
echo "Generated Moneybook.xcodeproj (bundle id $BUNDLE_ID, team ${DEVELOPMENT_TEAM:-none})"
