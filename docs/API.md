# Moneybook API

Base URL: the Worker URL (e.g. `https://moneybook.<you>.workers.dev`) or a self-hosted server (`http://host:8787`).
Source of truth: `server/src/service.ts` (logic) and `server/src/app.ts` (routes).

## Auth
Every `/api/*` request needs `Authorization: Bearer <API_TOKEN>`. `GET /api/receipts/...` also accepts `?token=` so `<img>` tags work.

## Data model (all ids are UUID strings; clients may supply their own `id` on create)
- **account_groups** `{id, name, kind: asset|liability|card, sort, updated_at, deleted}`
- **accounts** `{id, group_id, name, initial_balance, currency|null, include_in_totals 0/1, hidden 0/1, note, sort, updated_at, deleted}`
- **categories** `{id, type: expense|income, name, icon (emoji), parent_id|null (subcategory), sort, updated_at, deleted}`
- **transactions** `{id, type: expense|income|transfer, date 'YYYY-MM-DDTHH:MM' (user local time), amount (>0), account_id, to_account_id (transfers), category_id (null for transfers), note (short title), description (memo), receipt (blob key)|null, source: app|web|ai|api|import, created_at, updated_at, deleted}`
- **budgets** `{id, category_id|null (null = total), month 'YYYY-MM'|null (null = every month), amount, updated_at, deleted}`
- **settings** map: `currency` (ISO code, default USD), `timezone` (IANA, clients should set it), `week_start` ("0" Sunday / "1" Monday), `month_start_day` ("1".."28"), `default_account_id`.

`updated_at` is ms epoch from the server. Deletes are soft (`deleted = 1`).

## Sync
`GET /api/sync?since=<cursor>` → `{cursor, account_groups[], accounts[], categories[], transactions[], budgets[], settings{}}`
Returns all rows (including deleted tombstones) with `updated_at >= since`. Start with `since=0`, store `cursor`, upsert rows by id, drop rows where `deleted=1`. Rows at exactly `cursor` repeat on the next call; upsert makes that harmless.

## Endpoints
| Method | Path | Notes |
|---|---|---|
| GET | /api/health | no auth |
| GET/PATCH | /api/settings | PATCH with partial map |
| GET/POST | /api/account-groups, PATCH/DELETE /api/account-groups/:id | |
| GET/POST | /api/accounts, PATCH/DELETE /api/accounts/:id | POST `{name, group (name) or group_id, initial_balance?}` |
| GET | /api/balances | `{currency, assets, liabilities, total, accounts:[{id,name,group,group_kind,balance,include_in_totals,hidden}]}` |
| GET/POST | /api/categories, PATCH/DELETE /api/categories/:id | POST `{type, name, icon?, parent? (name) or parent_id?}` |
| GET | /api/transactions | query: `from, to` (YYYY-MM-DD inclusive), `type, account, category` (name or id), `q`, `limit` (≤5000), `offset`. Rows include `account_name, to_account_name, category_name, category_icon, parent_category_name, parent_category_icon` |
| POST | /api/transactions | `{type?, amount, date?, account? / account_id?, to_account? / to_account_id?, category? / category_id?, note?, description?}`. Names are matched case-insensitively; `"Food/Lunch"` picks a subcategory. Or `{transactions:[...]}` for a batch. |
| GET/PATCH/DELETE | /api/transactions/:id | PATCH changes only given fields |
| POST/DELETE | /api/transactions/:id/receipt | POST raw image bytes with `Content-Type: image/*` (≤10 MB) |
| GET | /api/receipts/<file> | the `receipt` key is `receipts/<file>` → `GET /api/receipts/<file>` |
| GET | /api/summary | `month=YYYY-MM` (honors month_start_day) or `from/to`. Returns `{from,to,currency,income,expense,net,count,expense_by_category[{category_id,name,icon,total,count,percent}],income_by_category[],by_day[{day,income,expense}],budgets[{budget_id,category_id,name,icon,budget,spent,remaining,percent}]}` |
| GET/PUT | /api/budgets, DELETE /api/budgets/:id | PUT `{category (name, or "Total"), amount, month?}`; amount 0 removes |

Errors: `{error: "message"}` with 400/401/404. Unknown names return the list of valid options in the message.

## MCP
`POST /mcp` (Bearer header) or `POST /mcp/<API_TOKEN>` (token in URL, for claude.ai custom connectors). Streamable HTTP, stateless.
Tools: `get_setup, add_transaction, add_transactions, list_transactions, update_transaction, delete_transaction, get_summary, get_balances, set_budget, create_category, create_account`.

## Running locally
```
cd server && npm install
API_TOKEN=dev DATA_DIR=./data npm start     # http://localhost:8787, also serves ../web
npm test
```
