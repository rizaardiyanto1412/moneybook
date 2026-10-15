import type { Sql } from "./db.js";
import * as svc from "./service.js";

// Minimal stateless MCP server (Streamable HTTP transport, JSON responses).
// Spec: https://modelcontextprotocol.io/specification

const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];

interface Tool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  annotations?: Record<string, unknown>;
  run: (sql: Sql, args: any) => Promise<unknown>;
}

const str = (description: string) => ({ type: "string", description });
const num = (description: string) => ({ type: "number", description });

const txFields = {
  type: { type: "string", enum: ["expense", "income", "transfer"], description: "Defaults to expense." },
  amount: num("Positive amount in the user's currency, e.g. 12.5"),
  category: str("Category name, e.g. 'Food', or 'Food/Lunch' for a subcategory. Call get_setup to see valid names. Omit for transfers."),
  account: str("Account paid from (or received into), e.g. 'Cash', 'Card'. Defaults to the user's default account."),
  to_account: str("Destination account, only for transfers."),
  note: str("Short title, usually the merchant or what it was, e.g. 'Starbucks'."),
  description: str("Optional longer memo, e.g. itemized receipt lines."),
  date: str("YYYY-MM-DD, YYYY-MM-DDTHH:MM, 'today' or 'yesterday'. Defaults to now in the user's timezone."),
};

const periodFields = {
  month: str("YYYY-MM. Defaults to the current month."),
  from: str("Start date YYYY-MM-DD (inclusive). Use instead of month for custom ranges."),
  to: str("End date YYYY-MM-DD (inclusive)."),
};

const TOOLS: Tool[] = [
  {
    name: "get_setup",
    description: "List the user's accounts (with balances), expense/income categories and settings (currency, timezone). Call this first if unsure which category/account names exist.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
    run: async (sql) => {
      const [bal, cats, settings] = await Promise.all([svc.balances(sql), svc.listCategories(sql), svc.getSettings(sql)]);
      const tree = (type: string) => cats.filter((c) => c.type === type && !c.parent_id).map((c) => ({
        name: c.name, icon: c.icon,
        subcategories: cats.filter((s) => s.parent_id === c.id).map((s) => s.name),
      }));
      const defaultAccount = bal.accounts.find((a) => a.id === settings.default_account_id)?.name;
      return {
        currency: settings.currency, timezone: settings.timezone, today: svc.nowLocal(settings.timezone).slice(0, 10),
        default_account: defaultAccount, accounts: bal.accounts.map((a) => ({ name: a.name, group: a.group, balance: a.balance })),
        expense_categories: tree("expense"), income_categories: tree("income"),
      };
    },
  },
  {
    name: "add_transaction",
    description: "Record an expense, income or transfer. Use for 'I spent...', 'log/note this expense', 'got paid...'. If the user shares a receipt photo, read it yourself and call this with the total, the merchant as note and the itemized lines in description. Pick the closest existing category.",
    inputSchema: { type: "object", properties: txFields, required: ["amount"] },
    run: (sql, args) => svc.createTransaction(sql, args, "ai"),
  },
  {
    name: "add_transactions",
    description: "Record several transactions at once (e.g. a list of expenses or a split receipt).",
    inputSchema: {
      type: "object",
      properties: { transactions: { type: "array", items: { type: "object", properties: txFields, required: ["amount"] } } },
      required: ["transactions"],
    },
    run: async (sql, args) => {
      const out = [];
      for (const t of args.transactions ?? []) out.push(await svc.createTransaction(sql, t, "ai"));
      return out;
    },
  },
  {
    name: "list_transactions",
    description: "Search transactions, newest first. Use to answer questions or to find the id of a transaction to edit/delete.",
    inputSchema: {
      type: "object",
      properties: {
        from: str("Start date YYYY-MM-DD (inclusive)"), to: str("End date YYYY-MM-DD (inclusive)"),
        type: { type: "string", enum: ["expense", "income", "transfer"] },
        category: str("Category name (includes its subcategories)"), account: str("Account name"),
        query: str("Text to search in note/description"), limit: num("Max rows, default 50"),
      },
    },
    annotations: { readOnlyHint: true },
    run: (sql, a) => svc.listTransactions(sql, { from: a.from, to: a.to, type: a.type, category: a.category, account: a.account, q: a.query, limit: a.limit ?? 50 }),
  },
  {
    name: "update_transaction",
    description: "Edit a transaction by id. Only the given fields change.",
    inputSchema: { type: "object", properties: { id: str("Transaction id"), ...txFields }, required: ["id"] },
    run: (sql, { id, ...rest }) => svc.updateTransaction(sql, id, rest),
  },
  {
    name: "delete_transaction",
    description: "Delete a transaction by id. Confirm with the user first if it's ambiguous which one they mean.",
    inputSchema: { type: "object", properties: { id: str("Transaction id") }, required: ["id"] },
    annotations: { destructiveHint: true },
    run: async (sql, { id }) => ({ deleted: await svc.deleteTransaction(sql, id) }),
  },
  {
    name: "get_summary",
    description: "Income, expense, net, spending by category (with %), daily totals and budget status for a month or date range.",
    inputSchema: { type: "object", properties: periodFields },
    annotations: { readOnlyHint: true },
    run: (sql, a) => svc.summary(sql, a),
  },
  {
    name: "get_balances",
    description: "Current balance of every account plus total assets, liabilities and net worth.",
    inputSchema: { type: "object", properties: {} },
    annotations: { readOnlyHint: true },
    run: (sql) => svc.balances(sql),
  },
  {
    name: "set_budget",
    description: "Set a monthly expense budget for a category (or 'Total'). Without month it applies to every month; amount 0 removes it.",
    inputSchema: {
      type: "object",
      properties: { category: str("Expense category name, or 'Total'"), amount: num("Budget amount"), month: str("Optional YYYY-MM override") },
      required: ["category", "amount"],
    },
    run: (sql, a) => svc.setBudget(sql, a),
  },
  {
    name: "create_category",
    description: "Create a new expense or income category (or subcategory via parent). Only when no existing category fits and the user agrees.",
    inputSchema: {
      type: "object",
      properties: { type: { type: "string", enum: ["expense", "income"] }, name: str("Name"), icon: str("One emoji"), parent: str("Parent category name for a subcategory") },
      required: ["type", "name"],
    },
    run: (sql, a) => svc.createCategory(sql, a),
  },
  {
    name: "create_account",
    description: "Create a new account, e.g. a new credit card or bank account.",
    inputSchema: {
      type: "object",
      properties: {
        name: str("Account name"), group: str("Group: Cash, Accounts, Card, Debit Card, Savings, Top-Up/Prepaid, Investments, Overdrafts, Loan, Insurance, Others"),
        initial_balance: num("Starting balance, default 0"),
      },
      required: ["name"],
    },
    run: (sql, a) => svc.createAccount(sql, a),
  },
];

type JsonRpc = { jsonrpc: "2.0"; id?: string | number | null; method: string; params?: any };

function result(id: JsonRpc["id"], value: unknown) {
  return { jsonrpc: "2.0", id, result: value };
}
function error(id: JsonRpc["id"], code: number, message: string) {
  return { jsonrpc: "2.0", id: id ?? null, error: { code, message } };
}

async function handleOne(sql: Sql, msg: JsonRpc) {
  const { id, method, params } = msg;
  switch (method) {
    case "initialize": {
      const requested = params?.protocolVersion;
      return result(id, {
        protocolVersion: PROTOCOL_VERSIONS.includes(requested) ? requested : PROTOCOL_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "moneybook", version: "1.0.0" },
        instructions: "Moneybook is the user's personal expense tracker. Use add_transaction to log expenses/income the user mentions, get_setup to see valid accounts/categories, and get_summary/list_transactions to answer spending questions. Amounts are in the user's currency.",
      });
    }
    case "ping":
      return result(id, {});
    case "tools/list":
      return result(id, { tools: TOOLS.map(({ run, ...t }) => t) });
    case "tools/call": {
      const tool = TOOLS.find((t) => t.name === params?.name);
      if (!tool) return error(id, -32602, `Unknown tool: ${params?.name}`);
      try {
        await svc.migrate(sql);
        const value = await tool.run(sql, params?.arguments ?? {});
        return result(id, { content: [{ type: "text", text: JSON.stringify(value, null, 2) }], structuredContent: Array.isArray(value) ? { items: value } : value });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        return result(id, { content: [{ type: "text", text: `Error: ${message}` }], isError: true });
      }
    }
    default:
      if (method?.startsWith("notifications/")) return null;
      return error(id, -32601, `Method not found: ${method}`);
  }
}

/** Handles a POSTed JSON-RPC body. Returns null when only notifications were sent (respond 202). */
export async function handleMcp(sql: Sql, body: unknown): Promise<unknown | null> {
  if (Array.isArray(body)) {
    const out = (await Promise.all(body.map((m) => handleOne(sql, m)))).filter(Boolean);
    return out.length ? out : null;
  }
  if (!body || typeof body !== "object" || (body as JsonRpc).jsonrpc !== "2.0") return error(null, -32600, "Invalid Request");
  return handleOne(sql, body as JsonRpc);
}

export const toolNames = TOOLS.map((t) => t.name);
