import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "./app.js";
import type { Deps } from "./db.js";
import { disk, sqlite } from "./node-adapters.js";

// Self-hosted entry (VPS / local dev): SQLite file + receipts on disk.
//   DATA_DIR   where moneybook.db, receipts/ and token live (default ./data)
//   API_TOKEN  bearer token; generated and saved to DATA_DIR/token when unset
//   PORT       default 8787

const dataDir = path.resolve(process.env.DATA_DIR ?? "data");
fs.mkdirSync(path.join(dataDir, "receipts"), { recursive: true });

function loadToken(): string {
  if (process.env.API_TOKEN) return process.env.API_TOKEN;
  const file = path.join(dataDir, "token");
  if (fs.existsSync(file)) return fs.readFileSync(file, "utf8").trim();
  const token = randomBytes(24).toString("base64url");
  fs.writeFileSync(file, token + "\n", { mode: 0o600 });
  return token;
}

const deps: Deps = { sql: sqlite(path.join(dataDir, "moneybook.db")), blobs: disk(dataDir), apiToken: loadToken() };
const app = createApp(() => deps);

const webDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../web");
const webRoot = path.relative(process.cwd(), webDir) || ".";
app.use("/*", serveStatic({ root: webRoot }));
app.get("*", serveStatic({ path: path.join(webRoot, "index.html") }));

const port = Number(process.env.PORT ?? 8787);
serve({ fetch: app.fetch, port, hostname: process.env.HOST ?? "0.0.0.0" }, () => {
  console.log(`Moneybook listening on http://localhost:${port}`);
  console.log(`Data: ${dataDir}`);
  if (!process.env.API_TOKEN) console.log(`API token: stored in ${path.join(dataDir, "token")}`);
});
