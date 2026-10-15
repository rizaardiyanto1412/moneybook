import { schemaStatements, type Sql } from "./db.js";

// Business logic shared by the REST API and the MCP tools.

export class ApiError extends Error {
  constructor(public status: number, message: string, public details?: unknown) {
    super(message);
  }
}

export type TxType = "expense" | "income" | "transfer";

export interface Account {
  id: string; group_id: string; name: string; initial_balance: number; currency: string | null;
  include_in_totals: number; hidden: number; note: string; sort: number; updated_at: number; deleted: number;
}
export interface AccountGroup { id: string; name: string; kind: string; sort: number; updated_at: number; deleted: number }
export interface Category {
  id: string; type: "expense" | "income"; name: string; icon: string; parent_id: string | null;
  sort: number; updated_at: number; deleted: number;
}
export interface Transaction {
  id: string; type: TxType; date: string; amount: number; account_id: string; to_account_id: string | null;
  category_id: string | null; note: string; description: string; receipt: string | null; source: string;
  created_at: number; updated_at: number; deleted: number;
}
export interface Budget { id: string; category_id: string | null; month: string | null; amount: number; updated_at: number; deleted: number }

// Monotonic clock so rows written in the same millisecond still sort for sync.
let lastStamp = 0;
export function stamp(): number {
  lastStamp = Math.max(Date.now(), lastStamp + 1);
  return lastStamp;
}

export const uuid = () => crypto.randomUUID();

const DEFAULT_GROUPS: [string, string][] = [
  ["Cash", "asset"], ["Accounts", "asset"], ["Card", "card"], ["Debit Card", "asset"], ["Savings", "asset"],
  ["Top-Up/Prepaid", "asset"], ["Investments", "asset"], ["Overdrafts", "liability"], ["Loan", "liability"],
  ["Insurance", "asset"], ["Others", "asset"],
];
const DEFAULT_ACCOUNTS: [string, string][] = [["Cash", "Cash"], ["Bank Account", "Accounts"], ["Card", "Card"]];
// Mirrors Money Manager's English seed data (see docs/realbyte-analysis.md §3).
const DEFAULT_EXPENSE: [string, string, string[]][] = [
  ["🍜", "Food", ["Lunch", "Dinner", "Eating out", "Beverages"]],
  ["👬🏻", "Social Life", ["Friend", "Fellowship", "Alumni", "Dues"]],
  ["🐶", "Pets", []],
  ["🚖", "Transport", ["Bus", "Subway", "Taxi", "Car"]],
  ["🖼", "Culture", ["Books", "Movie", "Music", "Apps"]],
  ["🪑", "Household", ["Appliances", "Furniture", "Kitchen", "Toiletries", "Chandlery"]],
  ["🧥", "Apparel", ["Clothing", "Fashion", "Shoes", "Laundry"]],
  ["💄", "Beauty", ["Cosmetics", "Makeup", "Accessories"]],
  ["🧘🏼", "Health", ["Yoga", "Hospital", "Medicine"]],
  ["📙", "Education", ["Schooling", "Textbooks", "School supplies", "Academy"]],
  ["🎁", "Gift", []],
  ["", "Other", []],
];
const DEFAULT_INCOME: [string, string, string[]][] = [
  ["🤑", "Allowance", []], ["💰", "Salary", []], ["💵", "Petty cash", []], ["🏅", "Bonus", []], ["", "Other", []],
];
export const DEFAULT_SETTINGS: Record<string, string> = {
  currency: "USD",
  timezone: "UTC",
  week_start: "0", // 0 = Sunday
  month_start_day: "1",
  default_account_id: "",
};

const migrated = new WeakSet<Sql>();

export async function migrate(sql: Sql): Promise<void> {
  if (migrated.has(sql)) return;
  await sql.batch(schemaStatements().map((query) => ({ query, params: [] })));
  const seeded = await sql.first("SELECT 1 FROM account_groups LIMIT 1");
  if (!seeded) await seed(sql);
  migrated.add(sql);
}

async function seed(sql: Sql) {
  const t = stamp();
  const stmts: { query: string; params: unknown[] }[] = [];
  const groupIds = new Map<string, string>();
  DEFAULT_GROUPS.forEach(([name, kind], i) => {
    const id = uuid();
    groupIds.set(name, id);
    stmts.push({ query: "INSERT INTO account_groups (id,name,kind,sort,updated_at) VALUES (?,?,?,?,?)", params: [id, name, kind, i, t] });
  });
  let cashId = "";
  DEFAULT_ACCOUNTS.forEach(([name, group], i) => {
    const id = uuid();
    if (name === "Cash") cashId = id;
    stmts.push({ query: "INSERT INTO accounts (id,group_id,name,sort,updated_at) VALUES (?,?,?,?,?)", params: [id, groupIds.get(group), name, i, t] });
  });
  for (const [type, list] of [["expense", DEFAULT_EXPENSE], ["income", DEFAULT_INCOME]] as const) {
    list.forEach(([icon, name, subs], i) => {
      const parentId = uuid();
      stmts.push({ query: "INSERT INTO categories (id,type,name,icon,sort,updated_at) VALUES (?,?,?,?,?,?)", params: [parentId, type, name, icon, i, t] });
      subs.forEach((sub, j) => {
        stmts.push({ query: "INSERT INTO categories (id,type,name,icon,parent_id,sort,updated_at) VALUES (?,?,?,?,?,?,?)", params: [uuid(), type, sub, "", parentId, j, t] });
      });
    });
  }
  for (const [key, value] of Object.entries({ ...DEFAULT_SETTINGS, default_account_id: cashId })) {
    stmts.push({ query: "INSERT OR IGNORE INTO settings (key,value,updated_at) VALUES (?,?,?)", params: [key, value, t] });
  }
  await sql.batch(stmts);
}

// ---------- settings ----------

export async function getSettings(sql: Sql): Promise<Record<string, string>> {
  const rows = await sql.all<{ key: string; value: string }>("SELECT key, value FROM settings");
  return { ...DEFAULT_SETTINGS, ...Object.fromEntries(rows.map((r) => [r.key, r.value])) };
}

export async function updateSettings(sql: Sql, patch: Record<string, unknown>) {
  const t = stamp();
  const stmts = Object.entries(patch).map(([key, value]) => ({
    query: "INSERT INTO settings (key,value,updated_at) VALUES (?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
    params: [key, String(value ?? ""), t],
  }));
  if (stmts.length) await sql.batch(stmts);
  return getSettings(sql);
}

/** Current wall-clock time in the user's timezone as 'YYYY-MM-DDTHH:MM'. */
export function nowLocal(timezone: string): string {
  let tz = timezone;
  try { new Intl.DateTimeFormat("en-US", { timeZone: tz }); } catch { tz = "UTC"; }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(new Date()).map((p) => [p.type, p.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

export function normalizeDate(input: unknown, timezone: string): string {
  if (input === undefined || input === null || input === "") return nowLocal(timezone);
  const s = String(input).trim();
  const lower = s.toLowerCase();
  if (lower === "today" || lower === "now") return nowLocal(timezone);
  if (lower === "yesterday") {
    const d = new Date(nowLocal(timezone).slice(0, 10) + "T12:00:00Z");
    d.setUTCDate(d.getUTCDate() - 1);
    return d.toISOString().slice(0, 10) + "T12:00";
  }
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (m) return `${s}T12:00`;
  m = s.match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})/);
  if (m) return `${m[1]}T${m[2]}:${m[3]}`;
  throw new ApiError(400, `Invalid date "${s}". Use YYYY-MM-DD or YYYY-MM-DDTHH:MM.`);
}

// ---------- lookup helpers ----------

const norm = (s: string) => s.trim().toLowerCase();

function pickByName<T extends { id: string; name: string }>(rows: T[], input: string, what: string): T {
  const q = norm(input);
  const byId = rows.find((r) => r.id === input);
  if (byId) return byId;
  const exact = rows.filter((r) => norm(r.name) === q);
  if (exact.length === 1) return exact[0];
  const partial = rows.filter((r) => norm(r.name).includes(q) || q.includes(norm(r.name)));
  if (exact.length === 0 && partial.length === 1) return partial[0];
  const candidates = exact.length ? exact : partial;
  throw new ApiError(400, candidates.length > 1
    ? `${what} "${input}" is ambiguous: ${candidates.map((r) => r.name).join(", ")}`
    : `Unknown ${what.toLowerCase()} "${input}". Valid options: ${rows.map((r) => r.name).join(", ")}`);
}

export async function listAccounts(sql: Sql, includeDeleted = false) {
  return sql.all<Account>(`SELECT * FROM accounts ${includeDeleted ? "" : "WHERE deleted=0"} ORDER BY sort, name`);
}
export async function listGroups(sql: Sql) {
  return sql.all<AccountGroup>("SELECT * FROM account_groups WHERE deleted=0 ORDER BY sort");
}
export async function listCategories(sql: Sql) {
  return sql.all<Category>("SELECT * FROM categories WHERE deleted=0 ORDER BY type, sort, name");
}

export async function resolveAccount(sql: Sql, input: string) {
  return pickByName(await listAccounts(sql), input, "Account");
}

/** Accepts an id, "Food", "Lunch" (a subcategory) or "Food/Lunch". */
export async function resolveCategory(sql: Sql, type: "expense" | "income", input: string): Promise<Category> {
  const all = (await listCategories(sql)).filter((c) => c.type === type);
  const byId = all.find((c) => c.id === input);
  if (byId) return byId;
  const [parentName, childName] = input.split(/\s*[/>:]\s*/);
  if (childName) {
    const parent = pickByName(all.filter((c) => !c.parent_id), parentName, "Category");
    return pickByName(all.filter((c) => c.parent_id === parent.id), childName, `Subcategory of ${parent.name}`);
  }
  const top = all.filter((c) => !c.parent_id);
  const exactTop = top.filter((c) => norm(c.name) === norm(input));
  if (exactTop.length === 1) return exactTop[0];
  const exactSub = all.filter((c) => c.parent_id && norm(c.name) === norm(input));
  if (exactSub.length === 1) return exactSub[0];
  try {
    return pickByName(top, input, "Category");
  } catch (e) {
    const subs = all.filter((c) => c.parent_id && norm(c.name).includes(norm(input)));
    if (subs.length === 1) return subs[0];
    throw new ApiError(400, `Unknown ${type} category "${input}". Valid options: ${top.map((c) => c.name).join(", ")}`);
  }
}

// ---------- accounts / groups / categories CRUD ----------

export async function createAccount(sql: Sql, body: Record<string, any>) {
  if (!body.name) throw new ApiError(400, "name is required");
  const groups = await listGroups(sql);
  const group = body.group_id ? groups.find((g) => g.id === body.group_id) : pickByName(groups, String(body.group ?? "Accounts"), "Account group");
  if (!group) throw new ApiError(400, "Unknown group_id");
  const id = body.id ?? uuid();
  await sql.run(
    "INSERT INTO accounts (id,group_id,name,initial_balance,currency,include_in_totals,hidden,note,sort,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
    id, group.id, String(body.name), Number(body.initial_balance ?? 0), body.currency ?? null,
    body.include_in_totals === false ? 0 : 1, body.hidden ? 1 : 0, String(body.note ?? ""), Number(body.sort ?? 999), stamp(),
  );
  return sql.first<Account>("SELECT * FROM accounts WHERE id=?", id);
}

export async function updateRow(sql: Sql, table: "accounts" | "categories" | "account_groups", id: string, body: Record<string, any>, allowed: string[]) {
  const sets: string[] = [];
  const params: unknown[] = [];
  for (const key of allowed) {
    if (key in body) {
      let v = body[key];
      if (typeof v === "boolean") v = v ? 1 : 0;
      sets.push(`${key}=?`);
      params.push(v);
    }
  }
  if (!sets.length) throw new ApiError(400, `Nothing to update. Allowed fields: ${allowed.join(", ")}`);
  const existing = await sql.first(`SELECT id FROM ${table} WHERE id=?`, id);
  if (!existing) throw new ApiError(404, "Not found");
  await sql.run(`UPDATE ${table} SET ${sets.join(",")}, updated_at=? WHERE id=?`, ...params, stamp(), id);
  return sql.first(`SELECT * FROM ${table} WHERE id=?`, id);
}

export async function softDelete(sql: Sql, table: "accounts" | "categories" | "account_groups" | "budgets", id: string) {
  const existing = await sql.first(`SELECT id FROM ${table} WHERE id=?`, id);
  if (!existing) throw new ApiError(404, "Not found");
  await sql.run(`UPDATE ${table} SET deleted=1, updated_at=? WHERE id=?`, stamp(), id);
}

export async function createGroup(sql: Sql, body: Record<string, any>) {
  if (!body.name) throw new ApiError(400, "name is required");
  const id = body.id ?? uuid();
  await sql.run("INSERT INTO account_groups (id,name,kind,sort,updated_at) VALUES (?,?,?,?,?)",
    id, String(body.name), String(body.kind ?? "asset"), Number(body.sort ?? 999), stamp());
  return sql.first<AccountGroup>("SELECT * FROM account_groups WHERE id=?", id);
}

export async function createCategory(sql: Sql, body: Record<string, any>) {
  const type = body.type === "income" ? "income" : "expense";
  if (!body.name) throw new ApiError(400, "name is required");
  let parentId: string | null = null;
  if (body.parent_id || body.parent) {
    const parent = await resolveCategory(sql, type, String(body.parent_id ?? body.parent));
    if (parent.parent_id) throw new ApiError(400, "Subcategories can only be one level deep");
    parentId = parent.id;
  }
  const id = body.id ?? uuid();
  await sql.run("INSERT INTO categories (id,type,name,icon,parent_id,sort,updated_at) VALUES (?,?,?,?,?,?,?)",
    id, type, String(body.name), String(body.icon ?? ""), parentId, Number(body.sort ?? 999), stamp());
  return sql.first<Category>("SELECT * FROM categories WHERE id=?", id);
}

// ---------- transactions ----------

export interface TxInput {
  id?: string; type?: string; amount?: number | string; date?: string;
  account?: string; account_id?: string; to_account?: string; to_account_id?: string;
  category?: string; category_id?: string; note?: string; description?: string; source?: string;
}

function parseAmount(v: unknown): number {
  const n = typeof v === "number" ? v : Number(String(v ?? "").replace(/[^0-9.\-]/g, ""));
  if (!Number.isFinite(n) || n === 0) throw new ApiError(400, "amount must be a non-zero number");
  return Math.round(Math.abs(n) * 100) / 100;
}

function parseType(v: unknown): TxType {
  const t = String(v ?? "expense").toLowerCase();
  if (t === "expense" || t === "income" || t === "transfer") return t;
  throw new ApiError(400, `type must be expense, income or transfer (got "${t}")`);
}

async function resolveTxRefs(sql: Sql, type: TxType, input: TxInput, settings: Record<string, string>) {
  const accountRef = input.account_id ?? input.account ?? settings.default_account_id;
  if (!accountRef) throw new ApiError(400, "account is required");
  const account = await resolveAccount(sql, accountRef);
  let toAccountId: string | null = null;
  let categoryId: string | null = null;
  if (type === "transfer") {
    const toRef = input.to_account_id ?? input.to_account;
    if (!toRef) throw new ApiError(400, "to_account is required for transfers");
    const to = await resolveAccount(sql, toRef);
    if (to.id === account.id) throw new ApiError(400, "Cannot transfer to the same account");
    toAccountId = to.id;
  } else {
    const catRef = input.category_id ?? input.category;
    if (catRef) categoryId = (await resolveCategory(sql, type, catRef)).id;
    else {
      const other = (await listCategories(sql)).find((c) => c.type === type && !c.parent_id && norm(c.name) === "other");
      categoryId = other?.id ?? null;
    }
  }
  return { accountId: account.id, toAccountId, categoryId };
}

export async function createTransaction(sql: Sql, input: TxInput, defaultSource = "app") {
  const settings = await getSettings(sql);
  const type = parseType(input.type);
  const amount = parseAmount(input.amount);
  const date = normalizeDate(input.date, settings.timezone);
  const refs = await resolveTxRefs(sql, type, input, settings);
  const id = input.id ?? uuid();
  const t = stamp();
  await sql.run(
    `INSERT INTO transactions (id,type,date,amount,account_id,to_account_id,category_id,note,description,source,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
    id, type, date, amount, refs.accountId, refs.toAccountId, refs.categoryId,
    String(input.note ?? ""), String(input.description ?? ""), String(input.source ?? defaultSource), t, t,
  );
  return getTransaction(sql, id);
}

export async function updateTransaction(sql: Sql, id: string, input: TxInput) {
  const existing = await sql.first<Transaction>("SELECT * FROM transactions WHERE id=? AND deleted=0", id);
  if (!existing) throw new ApiError(404, `Transaction ${id} not found`);
  const settings = await getSettings(sql);
  const type = input.type !== undefined ? parseType(input.type) : existing.type;
  const merged: TxInput = {
    account_id: input.account === undefined && input.account_id === undefined ? existing.account_id : input.account_id,
    account: input.account,
    to_account_id: input.to_account === undefined && input.to_account_id === undefined ? existing.to_account_id ?? undefined : input.to_account_id,
    to_account: input.to_account,
    category_id: input.category === undefined && input.category_id === undefined && type === existing.type ? existing.category_id ?? undefined : input.category_id,
    category: input.category,
  };
  const refs = await resolveTxRefs(sql, type, merged, settings);
  await sql.run(
    `UPDATE transactions SET type=?, date=?, amount=?, account_id=?, to_account_id=?, category_id=?, note=?, description=?, updated_at=? WHERE id=?`,
    type,
    input.date !== undefined ? normalizeDate(input.date, settings.timezone) : existing.date,
    input.amount !== undefined ? parseAmount(input.amount) : existing.amount,
    refs.accountId, refs.toAccountId, refs.categoryId,
    input.note !== undefined ? String(input.note) : existing.note,
    input.description !== undefined ? String(input.description) : existing.description,
    stamp(), id,
  );
  return getTransaction(sql, id);
}

export async function deleteTransaction(sql: Sql, id: string) {
  const existing = await sql.first<Transaction>("SELECT * FROM transactions WHERE id=? AND deleted=0", id);
  if (!existing) throw new ApiError(404, `Transaction ${id} not found`);
  await sql.run("UPDATE transactions SET deleted=1, updated_at=? WHERE id=?", stamp(), id);
  return existing;
}

export async function setReceipt(sql: Sql, id: string, key: string | null) {
  await sql.run("UPDATE transactions SET receipt=?, updated_at=? WHERE id=?", key, stamp(), id);
}

const TX_SELECT = `
  SELECT t.*, a.name AS account_name, ta.name AS to_account_name,
         c.name AS category_name, c.icon AS category_icon, p.name AS parent_category_name, p.icon AS parent_category_icon
  FROM transactions t
  LEFT JOIN accounts a ON a.id = t.account_id
  LEFT JOIN accounts ta ON ta.id = t.to_account_id
  LEFT JOIN categories c ON c.id = t.category_id
  LEFT JOIN categories p ON p.id = c.parent_id`;

export async function getTransaction(sql: Sql, id: string) {
  const row = await sql.first(`${TX_SELECT} WHERE t.id=?`, id);
  if (!row) throw new ApiError(404, `Transaction ${id} not found`);
  return row;
}

export interface TxQuery {
  from?: string; to?: string; type?: string; account?: string; category?: string; q?: string;
  limit?: number | string; offset?: number | string;
}

export async function listTransactions(sql: Sql, query: TxQuery) {
  const where = ["t.deleted=0"];
  const params: unknown[] = [];
  if (query.from) { where.push("t.date >= ?"); params.push(String(query.from).slice(0, 10)); }
  if (query.to) { where.push("t.date < ?"); params.push(String(query.to).slice(0, 10) + "T99"); }
  if (query.type) { where.push("t.type = ?"); params.push(parseType(query.type)); }
  if (query.account) {
    const acc = await resolveAccount(sql, query.account);
    where.push("(t.account_id = ? OR t.to_account_id = ?)"); params.push(acc.id, acc.id);
  }
  if (query.category) {
    const type = query.type === "income" ? "income" : "expense";
    const cat = await resolveCategory(sql, type, query.category);
    where.push("(t.category_id = ? OR c.parent_id = ?)"); params.push(cat.id, cat.id);
  }
  if (query.q) {
    where.push("(t.note LIKE ? OR t.description LIKE ?)");
    params.push(`%${query.q}%`, `%${query.q}%`);
  }
  const limit = Math.min(Number(query.limit ?? 200) || 200, 5000);
  const offset = Number(query.offset ?? 0) || 0;
  return sql.all(`${TX_SELECT} WHERE ${where.join(" AND ")} ORDER BY t.date DESC, t.created_at DESC LIMIT ? OFFSET ?`, ...params, limit, offset);
}

// ---------- reports ----------

/**
 * Resolves {month: 'YYYY-MM'} or {from,to} into an inclusive date range, honoring month_start_day.
 * Like Money Manager, a start day < 20 names the period after the month it starts in
 * (S=10: "March" = Mar 10–Apr 9) and >= 20 after the month it ends in (S=25: "March" = Feb 25–Mar 24).
 */
export function resolvePeriod(q: { month?: string; from?: string; to?: string }, settings: Record<string, string>) {
  if (q.from || q.to) return { from: q.from?.slice(0, 10) ?? "0000-01-01", to: q.to?.slice(0, 10) ?? "9999-12-31" };
  const month = q.month ?? nowLocal(settings.timezone).slice(0, 7);
  if (!/^\d{4}-\d{2}$/.test(month)) throw new ApiError(400, "month must be YYYY-MM");
  const startDay = Math.min(Math.max(Number(settings.month_start_day) || 1, 1), 28);
  const [y, m] = month.split("-").map(Number);
  const startMonth = startDay >= 20 ? m - 2 : m - 1; // zero-based
  const start = new Date(Date.UTC(y, startMonth, startDay));
  const end = new Date(Date.UTC(y, startMonth + 1, startDay - 1));
  return { from: start.toISOString().slice(0, 10), to: end.toISOString().slice(0, 10) };
}

export async function summary(sql: Sql, q: { month?: string; from?: string; to?: string }) {
  const settings = await getSettings(sql);
  const { from, to } = resolvePeriod(q, settings);
  const params = [from, to + "T99"];
  const totals = await sql.all<{ type: string; total: number; count: number }>(
    "SELECT type, SUM(amount) AS total, COUNT(*) AS count FROM transactions WHERE deleted=0 AND date >= ? AND date < ? GROUP BY type", ...params);
  const byCat = await sql.all<{ type: string; id: string | null; name: string | null; icon: string | null; total: number; count: number }>(`
    SELECT t.type, COALESCE(p.id, c.id) AS id, COALESCE(p.name, c.name) AS name, COALESCE(p.icon, c.icon) AS icon,
           SUM(t.amount) AS total, COUNT(*) AS count
    FROM transactions t
    LEFT JOIN categories c ON c.id = t.category_id
    LEFT JOIN categories p ON p.id = c.parent_id
    WHERE t.deleted=0 AND t.type != 'transfer' AND t.date >= ? AND t.date < ?
    GROUP BY t.type, COALESCE(p.id, c.id) ORDER BY total DESC`, ...params);
  const byDay = await sql.all<{ day: string; income: number; expense: number }>(`
    SELECT substr(date,1,10) AS day,
           SUM(CASE WHEN type='income' THEN amount ELSE 0 END) AS income,
           SUM(CASE WHEN type='expense' THEN amount ELSE 0 END) AS expense
    FROM transactions WHERE deleted=0 AND date >= ? AND date < ? GROUP BY day ORDER BY day`, ...params);
  const get = (type: string) => totals.find((r) => r.type === type)?.total ?? 0;
  const income = round(get("income"));
  const expense = round(get("expense"));

  // Budgets only make sense for a single month.
  let budgets: unknown[] = [];
  if (!q.from && !q.to) {
    const month = q.month ?? nowLocal(settings.timezone).slice(0, 7);
    budgets = await budgetStatus(sql, month, byCat.filter((r) => r.type === "expense"), expense);
  }
  return {
    from, to, currency: settings.currency, income, expense, net: round(income - expense),
    count: totals.reduce((n, r) => n + r.count, 0),
    expense_by_category: byCat.filter((r) => r.type === "expense").map(withPct(expense)),
    income_by_category: byCat.filter((r) => r.type === "income").map(withPct(income)),
    by_day: byDay,
    budgets,
  };
}

const round = (n: number) => Math.round(n * 100) / 100;
const withPct = (total: number) => (r: { id: string | null; name: string | null; icon: string | null; total: number; count: number }) => ({
  category_id: r.id, name: r.name ?? "Uncategorized", icon: r.icon ?? "", total: round(r.total), count: r.count,
  percent: total ? Math.round((r.total / total) * 1000) / 10 : 0,
});

export async function listBudgets(sql: Sql) {
  return sql.all<Budget>("SELECT * FROM budgets WHERE deleted=0");
}

/** Budget for a category in a month: month override wins over the default. */
async function budgetStatus(sql: Sql, month: string, spentByCat: { id: string | null; total: number }[], totalExpense: number) {
  const budgets = await listBudgets(sql);
  const cats = await listCategories(sql);
  const effective = new Map<string, Budget>();
  for (const b of budgets) {
    const key = b.category_id ?? "__total__";
    if (b.month && b.month !== month) continue;
    const prev = effective.get(key);
    if (!prev || (b.month && !prev.month)) effective.set(key, b);
  }
  return [...effective.entries()].map(([key, b]) => {
    const spent = key === "__total__" ? totalExpense : spentByCat.find((r) => r.id === key)?.total ?? 0;
    const cat = cats.find((c) => c.id === key);
    return {
      budget_id: b.id, category_id: b.category_id, name: cat?.name ?? "Total", icon: cat?.icon ?? "",
      budget: b.amount, spent: round(spent), remaining: round(b.amount - spent),
      percent: b.amount ? Math.round((spent / b.amount) * 1000) / 10 : 0,
    };
  });
}

export async function setBudget(sql: Sql, body: { category?: string; category_id?: string | null; month?: string | null; amount: number | string }) {
  let categoryId: string | null = null;
  const ref = body.category_id ?? body.category;
  if (ref && norm(String(ref)) !== "total") categoryId = (await resolveCategory(sql, "expense", String(ref))).id;
  const month = body.month || null;
  if (month && !/^\d{4}-\d{2}$/.test(month)) throw new ApiError(400, "month must be YYYY-MM");
  const amount = Number(body.amount);
  if (!Number.isFinite(amount) || amount < 0) throw new ApiError(400, "amount must be >= 0");
  const existing = await sql.first<Budget>(
    "SELECT * FROM budgets WHERE deleted=0 AND category_id IS ? AND month IS ?", categoryId, month);
  const t = stamp();
  if (existing) {
    if (amount === 0) await sql.run("UPDATE budgets SET deleted=1, updated_at=? WHERE id=?", t, existing.id);
    else await sql.run("UPDATE budgets SET amount=?, updated_at=? WHERE id=?", amount, t, existing.id);
    return { ...existing, amount, deleted: amount === 0 ? 1 : 0 };
  }
  const id = uuid();
  await sql.run("INSERT INTO budgets (id,category_id,month,amount,updated_at) VALUES (?,?,?,?,?)", id, categoryId, month, amount, t);
  return { id, category_id: categoryId, month, amount, updated_at: t, deleted: 0 };
}

export async function balances(sql: Sql) {
  const settings = await getSettings(sql);
  const rows = await sql.all<Account & { group_name: string; group_kind: string; balance: number }>(`
    SELECT a.*, g.name AS group_name, g.kind AS group_kind,
      a.initial_balance
      + COALESCE((SELECT SUM(amount) FROM transactions WHERE deleted=0 AND type='income' AND account_id=a.id), 0)
      - COALESCE((SELECT SUM(amount) FROM transactions WHERE deleted=0 AND type='expense' AND account_id=a.id), 0)
      - COALESCE((SELECT SUM(amount) FROM transactions WHERE deleted=0 AND type='transfer' AND account_id=a.id), 0)
      + COALESCE((SELECT SUM(amount) FROM transactions WHERE deleted=0 AND type='transfer' AND to_account_id=a.id), 0)
      AS balance
    FROM accounts a JOIN account_groups g ON g.id = a.group_id
    WHERE a.deleted=0 ORDER BY g.sort, a.sort, a.name`);
  const counted = rows.filter((r) => r.include_in_totals);
  const assets = round(counted.filter((r) => r.balance > 0).reduce((s, r) => s + r.balance, 0));
  const liabilities = round(counted.filter((r) => r.balance < 0).reduce((s, r) => s - r.balance, 0));
  return {
    currency: settings.currency, assets, liabilities, total: round(assets - liabilities),
    accounts: rows.map((r) => ({ id: r.id, name: r.name, group: r.group_name, group_kind: r.group_kind, balance: round(r.balance), include_in_totals: !!r.include_in_totals, hidden: !!r.hidden })),
  };
}

// ---------- sync ----------

export async function syncSince(sql: Sql, since: number) {
  const q = (table: string) => sql.all(`SELECT * FROM ${table} WHERE updated_at >= ?`, since);
  const [account_groups, accounts, categories, transactions, budgets, settingsRows] = await Promise.all([
    q("account_groups"), q("accounts"), q("categories"), q("transactions"), q("budgets"), q("settings"),
  ]);
  const all = [account_groups, accounts, categories, transactions, budgets, settingsRows].flat() as { updated_at: number }[];
  const cursor = all.reduce((m, r) => Math.max(m, r.updated_at), since);
  return { cursor, account_groups, accounts, categories, transactions, budgets, settings: await getSettings(sql) };
}

// ---------- bulk import ----------

const IMPORT_COLUMNS = {
  account_groups: ["id", "name", "kind", "sort"],
  accounts: ["id", "group_id", "name", "initial_balance", "currency", "include_in_totals", "hidden", "note", "sort"],
  categories: ["id", "type", "name", "icon", "parent_id", "sort"],
  transactions: ["id", "type", "date", "amount", "account_id", "to_account_id", "category_id", "note", "description", "source", "created_at"],
  budgets: ["id", "category_id", "month", "amount"],
} as const;

export type ImportData = { [K in keyof typeof IMPORT_COLUMNS]?: Record<string, unknown>[] } & { settings?: Record<string, unknown> };

/**
 * Upserts rows by id (idempotent). Each table is one statement fed by a JSON array via json_each,
 * which keeps D1 under its per-query parameter limit. With `replace`, existing rows are soft-deleted
 * first so clients receive tombstones for the seeded defaults.
 */
export async function importData(sql: Sql, data: ImportData, replace = false) {
  const t = stamp();
  const stmts: { query: string; params: unknown[] }[] = [];
  if (replace) {
    for (const table of Object.keys(IMPORT_COLUMNS)) {
      stmts.push({ query: `UPDATE ${table} SET deleted=1, updated_at=? WHERE deleted=0`, params: [t] });
    }
  }
  const counts: Record<string, number> = {};
  for (const [table, cols] of Object.entries(IMPORT_COLUMNS)) {
    const rows = data[table as keyof typeof IMPORT_COLUMNS];
    if (!rows?.length) continue;
    for (const r of rows) if (typeof r.id !== "string" || !r.id) throw new ApiError(400, `${table}: every row needs a string id`);
    counts[table] = rows.length;
    const extract = cols.map((c) => c === "created_at" ? `COALESCE(json_extract(value,'$.created_at'), ?)` : `json_extract(value,'$.${c}')`);
    const params: unknown[] = cols.includes("created_at" as never) ? [t] : [];
    stmts.push({
      query: `INSERT OR REPLACE INTO ${table} (${cols.join(",")},updated_at,deleted) SELECT ${extract.join(",")},?,0 FROM json_each(?)`,
      params: [...params, t, JSON.stringify(rows)],
    });
  }
  await sql.batch(stmts);
  if (data.settings) await updateSettings(sql, data.settings);
  return { imported: counts, replaced: replace };
}
