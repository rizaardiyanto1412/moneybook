import { Hono, type Context } from "hono";
import { cors } from "hono/cors";
import type { Deps } from "./db.js";
import { handleMcp } from "./mcp.js";
import * as auth from "./auth.js";
import * as svc from "./service.js";

type Env = { Variables: { deps: Deps } };

/** `getDeps` builds storage for a request (per-request on Workers, a singleton on Node). */
export function createApp(getDeps: (c: Context) => Deps) {
  const app = new Hono<Env>();

  app.onError((err, c) => {
    if (err instanceof svc.ApiError) return c.json({ error: err.message, details: err.details }, err.status as any);
    console.error(err);
    return c.json({ error: "Internal error", message: err.message }, 500);
  });

  app.use("*", async (c, next) => {
    c.set("deps", getDeps(c));
    await next();
  });

  app.get("/api/health", (c) => c.json({ ok: true }));

  // Token comes from the Authorization header, ?token= (for <img> tags) or the /mcp/:token path.
  const provided = (c: Context<Env>) => c.req.header("authorization")?.replace(/^Bearer\s+/i, "") ?? c.req.query("token") ?? "";
  const authorized = (c: Context<Env>, pathToken?: string) => {
    const expected = c.get("deps").apiToken;
    if (!expected) return false;
    const token = pathToken ?? provided(c);
    return !!token && timingSafeEqual(token, expected);
  };
  /** The API token, or a web-app session from email + password sign-in. */
  const authorizedOrSession = async (c: Context<Env>) =>
    authorized(c) || (await auth.checkSession(c.get("deps").sql, provided(c)));

  // ---------- MCP ----------
  const mcp = async (c: Context<Env>) => {
    if (!authorized(c, c.req.param("token"))) return c.json({ error: "Unauthorized" }, 401);
    if (c.req.method !== "POST") return c.body(null, 405, { Allow: "POST" });
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400); }
    const out = await handleMcp(c.get("deps").sql, body);
    return out === null ? c.body(null, 202) : c.json(out);
  };
  app.all("/mcp", mcp);
  app.all("/mcp/:token", mcp);

  // ---------- REST API ----------
  app.use("/api/*", cors({ origin: "*", allowHeaders: ["Authorization", "Content-Type"], allowMethods: ["GET", "POST", "PATCH", "PUT", "DELETE"] }));
  const sql = (c: Context<Env>) => c.get("deps").sql;
  const body = async (c: Context<Env>) => {
    try { return (await c.req.json()) as Record<string, any>; } catch { throw new svc.ApiError(400, "Body must be JSON"); }
  };

  // ---------- sign-in (open endpoints; registered before the auth guard) ----------
  app.get("/api/auth/status", async (c) => {
    await svc.migrate(sql(c));
    return c.json(await auth.status(sql(c)));
  });
  app.post("/api/auth/login", async (c) => {
    await svc.migrate(sql(c));
    if (!(await auth.status(sql(c))).hasPassword) throw new svc.ApiError(400, "No password set yet. Sign in with the API token first.");
    return c.json(await auth.login(sql(c), await body(c), c.req.header("user-agent") ?? ""));
  });

  app.use("/api/*", async (c, next) => {
    if (c.req.method === "OPTIONS") return next();
    await svc.migrate(c.get("deps").sql);
    if (!(await authorizedOrSession(c))) return c.json({ error: "Unauthorized" }, 401);
    await next();
  });

  // Signed-in only. With the API token you can (re)set the login without the current password.
  app.put("/api/auth/password", async (c) => {
    const master = authorized(c);
    return c.json(await auth.setPassword(sql(c), await body(c), master, master ? undefined : provided(c)));
  });
  app.post("/api/auth/logout", async (c) => {
    await auth.logout(sql(c), provided(c));
    return c.json({ ok: true });
  });
  app.post("/api/auth/logout-all", async (c) => {
    await auth.logoutAll(sql(c));
    return c.json({ ok: true });
  });

  app.get("/api/sync", async (c) => c.json(await svc.syncSince(sql(c), Number(c.req.query("since") ?? 0) || 0)));

  app.get("/api/settings", async (c) => c.json(await svc.getSettings(sql(c))));
  app.patch("/api/settings", async (c) => c.json(await svc.updateSettings(sql(c), await body(c))));

  app.get("/api/account-groups", async (c) => c.json(await svc.listGroups(sql(c))));
  app.post("/api/account-groups", async (c) => c.json(await svc.createGroup(sql(c), await body(c)), 201));
  app.patch("/api/account-groups/:id", async (c) =>
    c.json(await svc.updateRow(sql(c), "account_groups", c.req.param("id"), await body(c), ["name", "kind", "sort"])));
  app.delete("/api/account-groups/:id", async (c) => {
    await svc.softDelete(sql(c), "account_groups", c.req.param("id"));
    return c.json({ ok: true });
  });

  app.get("/api/accounts", async (c) => c.json(await svc.listAccounts(sql(c))));
  app.post("/api/accounts", async (c) => c.json(await svc.createAccount(sql(c), await body(c)), 201));
  app.patch("/api/accounts/:id", async (c) =>
    c.json(await svc.updateRow(sql(c), "accounts", c.req.param("id"), await body(c),
      ["name", "group_id", "initial_balance", "currency", "include_in_totals", "hidden", "note", "sort"])));
  app.delete("/api/accounts/:id", async (c) => {
    await svc.softDelete(sql(c), "accounts", c.req.param("id"));
    return c.json({ ok: true });
  });
  app.get("/api/balances", async (c) => c.json(await svc.balances(sql(c))));

  app.get("/api/categories", async (c) => c.json(await svc.listCategories(sql(c))));
  app.post("/api/categories", async (c) => c.json(await svc.createCategory(sql(c), await body(c)), 201));
  app.patch("/api/categories/:id", async (c) =>
    c.json(await svc.updateRow(sql(c), "categories", c.req.param("id"), await body(c), ["name", "icon", "sort", "parent_id"])));
  app.delete("/api/categories/:id", async (c) => {
    await svc.softDelete(sql(c), "categories", c.req.param("id"));
    return c.json({ ok: true });
  });

  app.get("/api/transactions", async (c) => c.json(await svc.listTransactions(sql(c), c.req.query())));
  app.get("/api/transactions/:id", async (c) => c.json(await svc.getTransaction(sql(c), c.req.param("id"))));
  app.post("/api/transactions", async (c) => {
    const b = await body(c);
    if (Array.isArray(b.transactions)) {
      const out = [];
      for (const t of b.transactions) out.push(await svc.createTransaction(sql(c), t, "api"));
      return c.json(out, 201);
    }
    return c.json(await svc.createTransaction(sql(c), b, "api"), 201);
  });
  app.patch("/api/transactions/:id", async (c) => c.json(await svc.updateTransaction(sql(c), c.req.param("id"), await body(c))));
  app.delete("/api/transactions/:id", async (c) => {
    await svc.deleteTransaction(sql(c), c.req.param("id"));
    return c.json({ ok: true });
  });

  // Receipt photos: POST raw image bytes with the image's Content-Type.
  app.post("/api/transactions/:id/receipt", async (c) => {
    const id = c.req.param("id");
    const tx = await svc.getTransaction(sql(c), id) as { receipt: string | null };
    const type = c.req.header("content-type") ?? "application/octet-stream";
    if (!type.startsWith("image/")) throw new svc.ApiError(400, "Content-Type must be image/*");
    const data = await c.req.arrayBuffer();
    if (data.byteLength > 10 * 1024 * 1024) throw new svc.ApiError(413, "Receipt must be under 10 MB");
    const ext = type.split("/")[1]?.split(";")[0].replace("jpeg", "jpg") ?? "bin";
    const key = `receipts/${id}-${Date.now()}.${ext}`;
    const { blobs } = c.get("deps");
    await blobs.put(key, data, type);
    if (tx.receipt) await blobs.delete(tx.receipt);
    await svc.setReceipt(sql(c), id, key);
    return c.json(await svc.getTransaction(sql(c), id));
  });
  app.delete("/api/transactions/:id/receipt", async (c) => {
    const id = c.req.param("id");
    const tx = await svc.getTransaction(sql(c), id) as { receipt: string | null };
    if (tx.receipt) await c.get("deps").blobs.delete(tx.receipt);
    await svc.setReceipt(sql(c), id, null);
    return c.json({ ok: true });
  });
  app.get("/api/receipts/*", async (c) => {
    const key = decodeURIComponent(c.req.path.replace(/^\/api\/receipts\//, "receipts/"));
    const blob = await c.get("deps").blobs.get(key);
    if (!blob) return c.json({ error: "Not found" }, 404);
    return c.body(blob.body as any, 200, { "Content-Type": blob.contentType, "Cache-Control": "private, max-age=31536000, immutable" });
  });

  // Bulk upsert used by the Money Manager importer (scripts/import-mmbak.ts). ?replace=1 wipes existing data first.
  app.post("/api/import", async (c) => {
    const replace = ["1", "true"].includes(c.req.query("replace") ?? "");
    return c.json(await svc.importData(sql(c), (await body(c)) as svc.ImportData, replace));
  });

  app.get("/api/summary", async (c) => c.json(await svc.summary(sql(c), c.req.query())));

  app.get("/api/budgets", async (c) => c.json(await svc.listBudgets(sql(c))));
  app.put("/api/budgets", async (c) => c.json(await svc.setBudget(sql(c), (await body(c)) as any)));
  app.delete("/api/budgets/:id", async (c) => {
    await svc.softDelete(sql(c), "budgets", c.req.param("id"));
    return c.json({ ok: true });
  });

  app.all("/api/*", (c) => c.json({ error: "Not found" }, 404));

  return app;
}

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
