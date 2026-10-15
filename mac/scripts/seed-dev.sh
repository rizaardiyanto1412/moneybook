#!/bin/bash
# Seeds a fresh local dev server with realistic sample data for the current and previous months.
# Usage: API=http://localhost:8787 TOKEN=dev ./seed-dev.sh
set -euo pipefail
API="${API:-http://localhost:8787}"
TOKEN="${TOKEN:-dev}"
H=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")
post() { curl -sf "${H[@]}" -X POST "$API$1" -d "$2" > /dev/null || echo "failed: $1 $2" >&2; }
put() { curl -sf "${H[@]}" -X PUT "$API$1" -d "$2" > /dev/null || echo "failed: $1 $2" >&2; }

# Day offsets relative to the 1st of a month: ym 0 = this month, ym -1 = previous month.
month() { date -v1d -v"${1}"m +%Y-%m; }
CUR=$(month +0)
PREV=$(month -1)
TODAY=$(date +%d)
d() { # d <YYYY-MM> <day> <HH:MM> -> date, clamped to today in the current month
  local day=$2
  if [[ "$1" == "$CUR" && 10#$day -gt 10#$TODAY ]]; then day=$TODAY; fi
  printf "%s-%02d T%s" "$1" "$((10#$day))" "$3" | tr -d ' '
}

# Accounts and subcategories
post /api/accounts '{"name":"Savings","group":"Savings","initial_balance":5000}'
post /api/accounts '{"name":"Wallet","group":"Cash","initial_balance":120}'
curl -sf "${H[@]}" -X PATCH "$API/api/accounts/$(curl -sf "${H[@]}" "$API/api/accounts" | python3 -c 'import json,sys;print([a["id"] for a in json.load(sys.stdin) if a["name"]=="Bank Account"][0])')" -d '{"initial_balance":2400}' > /dev/null
# The server's default seed already has Food/Lunch, Food/Dinner, Food/Beverages, Transport/Taxi, ...
post /api/categories '{"type":"expense","name":"Groceries","icon":"🛒","parent":"Food"}'

tx() { post /api/transactions "$1"; }
for M in "$PREV" "$CUR"; do
  tx "{\"type\":\"income\",\"amount\":4200,\"date\":\"$(d $M 01 09:00)\",\"account\":\"Bank Account\",\"category\":\"Salary\",\"note\":\"Monthly salary\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":1350,\"date\":\"$(d $M 02 10:00)\",\"account\":\"Bank Account\",\"category\":\"Household\",\"note\":\"Rent\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":86.40,\"date\":\"$(d $M 03 18:20)\",\"account\":\"Card\",\"category\":\"Food/Groceries\",\"note\":\"Whole Foods\",\"description\":\"Vegetables, bread, milk, coffee beans\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":4.80,\"date\":\"$(d $M 04 08:15)\",\"account\":\"Cash\",\"category\":\"Food/Beverages\",\"note\":\"Blue Bottle\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":14.50,\"date\":\"$(d $M 04 12:30)\",\"account\":\"Card\",\"category\":\"Food/Lunch\",\"note\":\"Sweetgreen\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":23.10,\"date\":\"$(d $M 05 22:40)\",\"account\":\"Card\",\"category\":\"Transport/Taxi\",\"note\":\"Uber home\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":62,\"date\":\"$(d $M 06 20:00)\",\"account\":\"Card\",\"category\":\"Social Life\",\"note\":\"Dinner with friends\",\"source\":\"app\"}"
  tx "{\"type\":\"transfer\",\"amount\":500,\"date\":\"$(d $M 07 09:30)\",\"account\":\"Bank Account\",\"to_account\":\"Savings\",\"note\":\"Monthly savings\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":45,\"date\":\"$(d $M 08 17:00)\",\"account\":\"Card\",\"category\":\"Health/Yoga\",\"note\":\"Yoga class\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":129.99,\"date\":\"$(d $M 09 14:10)\",\"account\":\"Card\",\"category\":\"Apparel\",\"note\":\"Uniqlo\",\"description\":\"Jacket\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":2.90,\"date\":\"$(d $M 10 08:40)\",\"account\":\"Cash\",\"category\":\"Transport/Subway\",\"note\":\"Metro\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":31.25,\"date\":\"$(d $M 11 19:30)\",\"account\":\"Card\",\"category\":\"Pets\",\"note\":\"Dog food\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":18,\"date\":\"$(d $M 12 13:00)\",\"account\":\"Cash\",\"category\":\"Culture\",\"note\":\"Cinema\",\"source\":\"app\"}"
  tx "{\"type\":\"income\",\"amount\":150,\"date\":\"$(d $M 12 16:00)\",\"account\":\"Cash\",\"category\":\"Bonus\",\"note\":\"Sold old bike\",\"source\":\"app\"}"
done
# Extra previous-month activity (late in the month)
for day in 15 18 21 24 27; do
  tx "{\"type\":\"expense\",\"amount\":$((20 + day)).75,\"date\":\"$(d $PREV $day 19:00)\",\"account\":\"Card\",\"category\":\"Food/Dinner\",\"note\":\"Dinner out\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":5.20,\"date\":\"$(d $PREV $day 08:30)\",\"account\":\"Cash\",\"category\":\"Food/Beverages\",\"note\":\"Coffee\",\"source\":\"app\"}"
done
tx "{\"type\":\"expense\",\"amount\":58,\"date\":\"$(d $PREV 20 11:00)\",\"account\":\"Card\",\"category\":\"Transport/Car\",\"note\":\"Shell\",\"source\":\"app\"}"
tx "{\"type\":\"expense\",\"amount\":75,\"date\":\"$(d $PREV 25 15:00)\",\"account\":\"Card\",\"category\":\"Gift\",\"note\":\"Birthday present\",\"source\":\"app\"}"
tx "{\"type\":\"expense\",\"amount\":49,\"date\":\"$(d $PREV 28 10:00)\",\"account\":\"Bank Account\",\"category\":\"Education\",\"note\":\"Online course\",\"source\":\"app\"}"

# Older months so the trend chart has some history
for k in 2 3 4 5; do
  M=$(month -$k)
  tx "{\"type\":\"income\",\"amount\":4200,\"date\":\"$M-01T09:00\",\"account\":\"Bank Account\",\"category\":\"Salary\",\"note\":\"Monthly salary\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":1350,\"date\":\"$M-02T10:00\",\"account\":\"Bank Account\",\"category\":\"Household\",\"note\":\"Rent\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":$((300 + k * 70)).40,\"date\":\"$M-14T18:00\",\"account\":\"Card\",\"category\":\"Food/Groceries\",\"note\":\"Groceries\",\"source\":\"app\"}"
  tx "{\"type\":\"expense\",\"amount\":$((120 + k * 35)),\"date\":\"$M-20T20:00\",\"account\":\"Card\",\"category\":\"Social Life\",\"note\":\"Going out\",\"source\":\"app\"}"
done

# Budgets
put /api/budgets '{"category":"Total","amount":2500}'
put /api/budgets '{"category":"Food","amount":400}'
put /api/budgets '{"category":"Transport","amount":120}'
put /api/budgets '{"category":"Social Life","amount":150}'

# An AI-created expense through MCP
curl -sf -H "Content-Type: application/json" -X POST "$API/mcp/$TOKEN" -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"add_transaction","arguments":{"amount":12.40,"category":"Food/Lunch","account":"Card","note":"Chipotle","description":"Burrito bowl + drink"}}}' > /dev/null
echo "Seeded $PREV and $CUR"
