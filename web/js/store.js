// Local replica of the server data, kept fresh with GET /api/sync?since=cursor.
// Rows live in memory (Maps) and are mirrored to localStorage so the app opens
// instantly and works read-only offline.

import { api } from "./api.js";
import { monthPeriod, periodOf, today, setCurrency } from "./format.js";

const CACHE_KEY = "mb.cache.v1";
const TABLES = ["account_groups", "accounts", "categories", "transactions", "budgets"];

export const db = {
  cursor: 0,
  account_groups: new Map(),
  accounts: new Map(),
  categories: new Map(),
  transactions: new Map(),
  budgets: new Map(),
  settings: {},
};

export const syncState = { last: 0, error: "", busy: false };
let version = 0;
const listeners = new Set();
export const subscribe = (fn) => (listeners.add(fn), () => listeners.delete(fn));
const emit = (info) => { version++; memo.clear(); listeners.forEach((fn) => fn(info)); };

export function loadCache() {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return false;
    const data = JSON.parse(raw);
    db.cursor = data.cursor || 0;
    for (const t of TABLES) db[t] = new Map((data[t] || []).map((r) => [r.id, r]));
    db.settings = data.settings || {};
    setCurrency(db.settings.currency, db.settings.decimals);
    emit({ fromCache: true });
    return true;
  } catch { return false; }
}

let saveTimer;
function saveCache() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const out = { cursor: db.cursor, settings: db.settings };
    for (const t of TABLES) out[t] = [...db[t].values()];
    try { localStorage.setItem(CACHE_KEY, JSON.stringify(out)); } catch { /* quota: keep in-memory only */ }
  }, 300);
}

export function clearCache() {
  localStorage.removeItem(CACHE_KEY);
  db.cursor = 0;
  for (const t of TABLES) db[t] = new Map();
  db.settings = {};
}

let inflight = null;
/** Pull changes since the cursor. Returns true when something changed. */
export function sync() {
  if (inflight) return inflight;
  syncState.busy = true;
  inflight = (async () => {
    try {
      const data = await api(`/api/sync?since=${db.cursor}`);
      const prev = db.cursor;
      const newIds = [];
      let changed = false;
      for (const t of TABLES) {
        for (const row of data[t] || []) {
          if (row.updated_at > prev || prev === 0) changed = true;
          if (row.deleted) { if (db[t].delete(row.id)) changed = true; continue; }
          if (t === "transactions" && !db[t].has(row.id) && prev !== 0) newIds.push(row.id);
          db[t].set(row.id, row);
        }
      }
      if (JSON.stringify(data.settings) !== JSON.stringify(db.settings)) { db.settings = data.settings || {}; changed = true; }
      setCurrency(db.settings.currency, db.settings.decimals);
      db.cursor = data.cursor || prev;
      syncState.last = Date.now();
      syncState.error = "";
      if (changed) { saveCache(); emit({ newIds }); }
      return changed;
    } catch (e) {
      syncState.error = e.message;
      throw e;
    } finally {
      syncState.busy = false;
      inflight = null;
    }
  })();
  return inflight;
}

/** Apply a row returned by a mutation right away (sync will confirm it). */
export function upsertLocal(table, row) {
  if (!row?.id) return;
  if (row.deleted) db[table].delete(row.id); else db[table].set(row.id, row);
  emit({});
}
export function removeLocal(table, id) { db[table].delete(id); emit({}); }

// ---------- derived data (memoized per data version) ----------

const memo = new Map();
const cached = (key, fn) => { if (!memo.has(key)) memo.set(key, fn()); return memo.get(key); };

export const startDay = () => Number(db.settings.month_start_day) || 1;
export const weekStart = () => Number(db.settings.week_start) || 0;
export const currentPeriod = () => periodOf(today(), startDay());
export const periodRange = (ym) => monthPeriod(ym, startDay());

const bySort = (a, b) => (a.sort - b.sort) || a.name.localeCompare(b.name);

export const groups = () => cached("groups", () => [...db.account_groups.values()].sort(bySort));
export const accounts = () => cached("accounts", () => [...db.accounts.values()].sort(bySort));
export const account = (id) => db.accounts.get(id);
export const category = (id) => db.categories.get(id);

/** Top-level categories of a type, each with `children`. */
export function categoryTree(type) {
  return cached(`tree:${type}`, () => {
    const all = [...db.categories.values()].filter((c) => c.type === type);
    const top = all.filter((c) => !c.parent_id || !db.categories.has(c.parent_id)).sort(bySort);
    return top.map((c) => ({ ...c, children: all.filter((s) => s.parent_id === c.id).sort(bySort) }));
  });
}

/** Display info for a transaction's category: {icon, name, sub}. */
export function catInfo(tx) {
  if (tx.type === "transfer") return { icon: "↔︎", name: "Transfer", sub: "", topId: null };
  const c = db.categories.get(tx.category_id);
  if (!c) return { icon: "", name: tx.category_name || "Uncategorized", sub: "", topId: null };
  const p = c.parent_id ? db.categories.get(c.parent_id) : null;
  return p ? { icon: p.icon, name: p.name, sub: c.name, topId: p.id } : { icon: c.icon, name: c.name, sub: "", topId: c.id };
}

/** All live transactions, newest first. */
export const allTx = () => cached("tx", () =>
  [...db.transactions.values()].sort((a, b) => (b.date < a.date ? -1 : b.date > a.date ? 1 : (b.created_at - a.created_at))));

/** Transactions between from..to (inclusive dates), optional filter fn. */
export function txRange(from, to, filter) {
  const hi = to + "T99";
  return allTx().filter((t) => t.date >= from && t.date < hi && (!filter || filter(t)));
}

export function totals(list) {
  let income = 0, expense = 0;
  for (const t of list) { if (t.type === "income") income += t.amount; else if (t.type === "expense") expense += t.amount; }
  return { income: r2(income), expense: r2(expense), total: r2(income - expense) };
}
const r2 = (n) => Math.round(n * 100) / 100;

/** Same logic as server balances(). */
export function balances() {
  return cached("balances", () => {
    const bal = new Map(accounts().map((a) => [a.id, a.initial_balance || 0]));
    for (const t of db.transactions.values()) {
      if (t.type === "income") bal.set(t.account_id, (bal.get(t.account_id) ?? 0) + t.amount);
      else if (t.type === "expense") bal.set(t.account_id, (bal.get(t.account_id) ?? 0) - t.amount);
      else {
        bal.set(t.account_id, (bal.get(t.account_id) ?? 0) - t.amount);
        if (t.to_account_id) bal.set(t.to_account_id, (bal.get(t.to_account_id) ?? 0) + t.amount);
      }
    }
    const rows = accounts().map((a) => ({ ...a, balance: r2(bal.get(a.id) ?? 0), group: db.account_groups.get(a.group_id) }));
    const counted = rows.filter((r) => r.include_in_totals);
    const assets = r2(counted.filter((r) => r.balance > 0).reduce((s, r) => s + r.balance, 0));
    const liabilities = r2(counted.filter((r) => r.balance < 0).reduce((s, r) => s - r.balance, 0));
    return { rows, assets, liabilities, total: r2(assets - liabilities) };
  });
}

/** An account's balance right after each of its transactions, by transaction id. */
export function runningBalances(id) {
  return cached(`running:${id}`, () => {
    let bal = account(id)?.initial_balance || 0;
    const out = new Map();
    const list = allTx();
    for (let i = list.length - 1; i >= 0; i--) {
      const t = list[i];
      if (t.account_id !== id && t.to_account_id !== id) continue;
      if (t.type === "income") bal += t.amount;
      else if (t.type === "expense") bal -= t.amount;
      else { if (t.account_id === id) bal -= t.amount; if (t.to_account_id === id) bal += t.amount; }
      out.set(t.id, r2(bal));
    }
    return out;
  });
}

/** Spending per top-level category for a list: [{id, name, icon, total, count, percent}] desc. */
export function byCategory(list, type) {
  const m = new Map();
  let sum = 0;
  for (const t of list) {
    if (t.type !== type) continue;
    const info = catInfo(t);
    const key = info.topId || "none";
    const e = m.get(key) || { id: info.topId, name: info.name, icon: info.icon, total: 0, count: 0 };
    e.total += t.amount; e.count++; sum += t.amount;
    m.set(key, e);
  }
  return [...m.values()].map((e) => ({ ...e, total: r2(e.total), percent: sum ? (e.total / sum) * 100 : 0 }))
    .sort((a, b) => b.total - a.total);
}

/** Effective budgets for a period: month-specific overrides beat "every month" (server rule). */
export function budgetStatus(ym, list) {
  const effective = new Map();
  for (const b of db.budgets.values()) {
    if (b.month && b.month !== ym) continue;
    const key = b.category_id ?? "__total__";
    const prev = effective.get(key);
    if (!prev || (b.month && !prev.month)) effective.set(key, b);
  }
  const spentBy = new Map(byCategory(list, "expense").map((r) => [r.id, r.total]));
  const totalExp = totals(list).expense;
  return [...effective.entries()].map(([key, b]) => {
    const cat = db.categories.get(key);
    const spent = key === "__total__" ? totalExp : spentBy.get(key) ?? 0;
    return {
      id: b.id, category_id: b.category_id, month: b.month, name: cat?.name ?? "Total", icon: cat?.icon ?? "", isTotal: key === "__total__",
      budget: b.amount, spent: r2(spent), remaining: r2(b.amount - spent), percent: b.amount ? (spent / b.amount) * 100 : 0,
    };
  }).filter((b) => b.isTotal || b.category_id && db.categories.has(b.category_id))
    .sort((a, b) => (b.isTotal - a.isTotal) || b.budget - a.budget);
}

export const getVersion = () => version;
