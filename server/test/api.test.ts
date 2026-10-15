import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { beforeEach, test } from "node:test";
import { createApp } from "../src/app.js";
import { disk, sqlite } from "../src/node-adapters.js";

const TOKEN = "test-token";
let app: ReturnType<typeof createApp>;

beforeEach(() => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "moneybook-"));
  const deps = { sql: sqlite(":memory:"), blobs: disk(dir), apiToken: TOKEN };
  app = createApp(() => deps);
});

async function api(method: string, url: string, body?: unknown, headers: Record<string, string> = {}) {
  const res = await app.request(url, {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json", ...headers },
    body: (body === undefined ? undefined : body instanceof Uint8Array ? body : JSON.stringify(body)) as any,
  });
  const text = await res.text();
  let json: any;
  try { json = JSON.parse(text); } catch { json = text; }
  return { status: res.status, json };
}

async function mcp(method: string, params?: unknown, id = 1) {
  return (await api("POST", "/mcp", { jsonrpc: "2.0", id, method, params })).json;
}

test("rejects missing token", async () => {
  const res = await app.request("/api/accounts");
  assert.equal(res.status, 401);
  const viaPath = await app.request(`/mcp/wrong`, { method: "POST", body: "{}" });
  assert.equal(viaPath.status, 401);
});

test("seeds defaults", async () => {
  const { json: accounts } = await api("GET", "/api/accounts");
  assert.deepEqual(accounts.map((a: any) => a.name), ["Cash", "Bank Account", "Card"]);
  const { json: cats } = await api("GET", "/api/categories");
  assert.ok(cats.some((c: any) => c.name === "Food" && c.type === "expense"));
  const { json: settings } = await api("GET", "/api/settings");
  assert.equal(settings.currency, "USD");
  assert.ok(settings.default_account_id);
});

test("creates transactions by name and computes balances and summary", async () => {
  let r = await api("POST", "/api/transactions", { amount: 12.5, category: "food", note: "Lunch", date: "2026-10-05" });
  assert.equal(r.status, 201, JSON.stringify(r.json));
  assert.equal(r.json.account_name, "Cash");
  assert.equal(r.json.category_name, "Food");
  assert.equal(r.json.date, "2026-10-05T12:00");
  r = await api("POST", "/api/transactions", { type: "income", amount: "1,000", category: "Salary", account: "bank", date: "2026-10-01T09:00" });
  assert.equal(r.status, 201, JSON.stringify(r.json));
  r = await api("POST", "/api/transactions", { type: "transfer", amount: 200, account: "Bank Account", to_account: "Cash", date: "2026-10-02" });
  assert.equal(r.status, 201, JSON.stringify(r.json));

  const { json: bal } = await api("GET", "/api/balances");
  const byName = Object.fromEntries(bal.accounts.map((a: any) => [a.name, a.balance]));
  assert.equal(byName["Cash"], 187.5);
  assert.equal(byName["Bank Account"], 800);
  assert.equal(bal.total, 987.5);

  const { json: sum } = await api("GET", "/api/summary?month=2026-10");
  assert.equal(sum.income, 1000);
  assert.equal(sum.expense, 12.5);
  assert.equal(sum.expense_by_category[0].name, "Food");
  assert.equal(sum.expense_by_category[0].percent, 100);
});

test("validation errors list valid options", async () => {
  const r = await api("POST", "/api/transactions", { amount: 5, category: "Spaceships" });
  assert.equal(r.status, 400);
  assert.match(r.json.error, /Valid options: .*Food/);
});

test("subcategories roll up to their parent", async () => {
  await api("POST", "/api/categories", { type: "expense", name: "Coffee", parent: "Food" });
  const r = await api("POST", "/api/transactions", { amount: 4, category: "Food/Coffee", date: "2026-10-03" });
  assert.equal(r.json.parent_category_name, "Food");
  const r2 = await api("POST", "/api/transactions", { amount: 6, category: "coffee", date: "2026-10-03" });
  assert.equal(r2.json.category_name, "Coffee");
  const { json: sum } = await api("GET", "/api/summary?from=2026-10-01&to=2026-10-31");
  assert.equal(sum.expense_by_category[0].name, "Food");
  assert.equal(sum.expense_by_category[0].total, 10);
  const { json: list } = await api("GET", "/api/transactions?category=Food");
  assert.equal(list.length, 2);
});

test("update, delete and sync tombstones", async () => {
  const { json: tx } = await api("POST", "/api/transactions", { amount: 10, category: "Transport" });
  const { json: sync1 } = await api("GET", "/api/sync?since=0");
  assert.ok(sync1.transactions.some((t: any) => t.id === tx.id));
  const cursor = sync1.cursor;

  const { json: upd } = await api("PATCH", `/api/transactions/${tx.id}`, { amount: 11, note: "Taxi" });
  assert.equal(upd.amount, 11);
  assert.equal(upd.category_name, "Transport");
  await api("DELETE", `/api/transactions/${tx.id}`);
  const { json: sync2 } = await api("GET", `/api/sync?since=${cursor}`);
  const row = sync2.transactions.find((t: any) => t.id === tx.id);
  assert.equal(row.deleted, 1);
  assert.equal(sync2.accounts.length, 0);
  const { json: list } = await api("GET", "/api/transactions");
  assert.equal(list.length, 0);
});

test("budgets: default plus monthly override", async () => {
  await api("PUT", "/api/budgets", { category: "Food", amount: 300 });
  await api("PUT", "/api/budgets", { category: "Food", amount: 100, month: "2026-11" });
  await api("POST", "/api/transactions", { amount: 50, category: "Food", date: "2026-11-02" });
  const { json: oct } = await api("GET", "/api/summary?month=2026-10");
  assert.equal(oct.budgets[0].budget, 300);
  const { json: nov } = await api("GET", "/api/summary?month=2026-11");
  assert.equal(nov.budgets[0].budget, 100);
  assert.equal(nov.budgets[0].spent, 50);
  assert.equal(nov.budgets[0].percent, 50);
});

test("month_start_day shifts the month window", async () => {
  await api("PATCH", "/api/settings", { month_start_day: 10 });
  let { json } = await api("GET", "/api/summary?month=2026-03");
  assert.equal(json.from, "2026-03-10");
  assert.equal(json.to, "2026-04-09");
  await api("PATCH", "/api/settings", { month_start_day: 25 });
  ({ json } = await api("GET", "/api/summary?month=2026-03"));
  assert.equal(json.from, "2026-02-25");
  assert.equal(json.to, "2026-03-24");
});

test("receipt upload and download", async () => {
  const { json: tx } = await api("POST", "/api/transactions", { amount: 3 });
  const png = new Uint8Array([137, 80, 78, 71, 1, 2, 3]);
  const up = await api("POST", `/api/transactions/${tx.id}/receipt`, png, { "Content-Type": "image/png" });
  assert.equal(up.status, 200, JSON.stringify(up.json));
  assert.match(up.json.receipt, /^receipts\/.+\.png$/);
  const res = await app.request(`/api/${up.json.receipt.replace(/^receipts\//, "receipts/")}?token=${TOKEN}`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/png");
  assert.deepEqual(new Uint8Array(await res.arrayBuffer()), png);
});

test("MCP: initialize, list tools, add and summarize", async () => {
  const init = await mcp("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } });
  assert.equal(init.result.serverInfo.name, "moneybook");
  const notif = await api("POST", "/mcp", { jsonrpc: "2.0", method: "notifications/initialized" });
  assert.equal(notif.status, 202);

  const tools = await mcp("tools/list");
  const names = tools.result.tools.map((t: any) => t.name);
  for (const n of ["add_transaction", "get_summary", "list_transactions", "update_transaction", "delete_transaction", "get_setup"]) assert.ok(names.includes(n), n);

  const add = await mcp("tools/call", { name: "add_transaction", arguments: { amount: 42, category: "Food", note: "Dinner", account: "Card" } });
  assert.equal(add.result.isError, undefined, add.result.content[0].text);
  assert.equal(add.result.structuredContent.source, "ai");
  assert.equal(add.result.structuredContent.account_name, "Card");

  const bad = await mcp("tools/call", { name: "add_transaction", arguments: { amount: 1, category: "nope" } });
  assert.equal(bad.result.isError, true);

  const setup = await mcp("tools/call", { name: "get_setup", arguments: {} });
  assert.equal(setup.result.structuredContent.default_account, "Cash");

  const sum = await mcp("tools/call", { name: "get_summary", arguments: {} });
  assert.equal(sum.result.structuredContent.expense, 42);

  // Token in the path works too (for clients that can't set headers).
  const res = await app.request(`/mcp/${TOKEN}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 9, method: "ping" }) });
  assert.equal(res.status, 200);
});

test("email + password sign-in creates a session that works like the token", async () => {
  const open = (method: string, url: string, body?: unknown, headers: Record<string, string> = {}) =>
    api(method, url, body, { Authorization: "", ...headers });

  assert.deepEqual((await open("GET", "/api/auth/status")).json, { hasPassword: false, email: null });
  assert.equal((await open("POST", "/api/auth/login", { email: "a@b.co", password: "whatever1" })).status, 400);

  // Only the API token (or a session) can set the login.
  assert.equal((await open("PUT", "/api/auth/password", { email: "Me@Example.com", password: "hunter22" })).status, 401);
  assert.equal((await api("PUT", "/api/auth/password", { email: "me@example.com", password: "short" })).status, 400);
  const set = await api("PUT", "/api/auth/password", { email: "Me@Example.com", password: "hunter22" });
  assert.equal(set.status, 200);
  assert.deepEqual(set.json, { hasPassword: true, email: "me@example.com" });

  assert.equal((await open("POST", "/api/auth/login", { email: "me@example.com", password: "nope-nope" })).status, 401);
  const ok = await open("POST", "/api/auth/login", { email: " ME@example.com ", password: "hunter22" });
  assert.equal(ok.status, 200);
  const session = ok.json.session as string;
  assert.match(session, /^s_/);

  const asSession = (method: string, url: string, body?: unknown) => api(method, url, body, { Authorization: `Bearer ${session}` });
  assert.equal((await asSession("GET", "/api/accounts")).status, 200);
  // Sessions don't open MCP; that stays on the API token.
  assert.equal((await app.request("/mcp", { method: "POST", headers: { Authorization: `Bearer ${session}` }, body: "{}" })).status, 401);

  // Changing the password from a session needs the current one, and keeps that session.
  assert.equal((await asSession("PUT", "/api/auth/password", { email: "me@example.com", password: "newpass99", current: "bad" })).status, 403);
  const other = (await open("POST", "/api/auth/login", { email: "me@example.com", password: "hunter22" })).json.session;
  assert.equal((await asSession("PUT", "/api/auth/password", { email: "me@example.com", password: "newpass99", current: "hunter22" })).status, 200);
  assert.equal((await asSession("GET", "/api/accounts")).status, 200);
  assert.equal((await api("GET", "/api/accounts", undefined, { Authorization: `Bearer ${other}` })).status, 401);

  assert.equal((await asSession("POST", "/api/auth/logout")).status, 200);
  assert.equal((await asSession("GET", "/api/accounts")).status, 401);
});

test("the API token can be shown to a session that confirms the password", async () => {
  await api("PUT", "/api/auth/password", { email: "me@example.com", password: "hunter22" });
  const session = (await api("POST", "/api/auth/login", { email: "me@example.com", password: "hunter22" }, { Authorization: "" })).json.session;
  const asSession = (body: unknown) => api("POST", "/api/auth/api-token", body, { Authorization: `Bearer ${session}` });
  assert.equal((await api("POST", "/api/auth/api-token", { password: "hunter22" }, { Authorization: "" })).status, 401);
  assert.equal((await asSession({})).status, 403);
  assert.equal((await asSession({ password: "wrong-one" })).status, 403);
  const ok = await asSession({ password: "hunter22" });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.token, TOKEN);
  // With the token itself, no password is needed.
  assert.equal((await api("POST", "/api/auth/api-token", {})).json.token, TOKEN);
});

test("login is rate limited after repeated failures", async () => {
  await api("PUT", "/api/auth/password", { email: "me@example.com", password: "hunter22" });
  const tryLogin = (password: string) => api("POST", "/api/auth/login", { email: "me@example.com", password }, { Authorization: "" });
  for (let i = 0; i < 5; i++) assert.equal((await tryLogin("wrong-" + i)).status, 401);
  const blocked = await tryLogin("hunter22");
  assert.equal(blocked.status, 429);
  assert.match(blocked.json.error, /Too many attempts/);
});
