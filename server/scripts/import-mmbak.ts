// Imports a Realbyte Money Manager backup (.mmbak = raw SQLite) into Moneybook.
//
//   npx tsx scripts/import-mmbak.ts <backup.mmbak> --url https://moneybook.example.workers.dev --token <API_TOKEN> [--replace] [--dry-run] [--inspect]
//
// --replace   soft-delete everything currently in Moneybook first (use for the first import)
// --dry-run   convert and print counts without uploading
// --inspect   print the backup's tables/columns (useful when a mapping is missing)
//
// Format notes come from docs/realbyte-analysis.md: Android backups have INOUTCOME/ASSETS/ZCATEGORY,
// iPhone backups use Core Data tables (ZINOUTCOME/ZASSET/ZCATEGORY) with dates in seconds since 2001.

import { DatabaseSync } from "node:sqlite";
import { convert } from "./mmbak.js";

function arg(name: string) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : undefined;
}
const flag = (name: string) => process.argv.includes(`--${name}`);

const file = process.argv[2];
if (!file || file.startsWith("--")) {
  console.error("Usage: npx tsx scripts/import-mmbak.ts <backup.mmbak> --url <server> --token <token> [--replace] [--dry-run] [--inspect]");
  process.exit(1);
}

const db = new DatabaseSync(file, { readOnly: true });

if (flag("inspect")) {
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all() as { name: string }[];
  for (const { name } of tables) {
    const cols = (db.prepare(`PRAGMA table_info("${name}")`).all() as { name: string }[]).map((c) => c.name);
    const count = (db.prepare(`SELECT COUNT(*) AS n FROM "${name}"`).get() as { n: number }).n;
    console.log(`${name} (${count} rows): ${cols.join(", ")}`);
  }
  process.exit(0);
}

const result = convert(db, Intl.DateTimeFormat().resolvedOptions().timeZone);
for (const w of result.warnings) console.warn(`warning: ${w}`);
console.log(`Detected ${result.flavor} backup:`, Object.fromEntries(Object.entries(result.data).filter(([k]) => k !== "settings").map(([k, v]) => [k, (v as unknown[]).length])));
console.log("Settings:", result.data.settings);

if (flag("dry-run")) process.exit(0);

const url = (arg("url") ?? process.env.MONEYBOOK_URL ?? "").replace(/\/$/, "");
const token = arg("token") ?? process.env.MONEYBOOK_TOKEN;
if (!url || !token) {
  console.error("Missing --url/--token (or MONEYBOOK_URL/MONEYBOOK_TOKEN)");
  process.exit(1);
}

async function post(body: unknown, replace: boolean) {
  const res = await fetch(`${url}/api/import${replace ? "?replace=1" : ""}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`Import failed (${res.status}): ${await res.text()}`);
  return res.json();
}

// Reference data and settings go first (with --replace); transactions follow in chunks
// small enough for D1's statement-size limit.
const { transactions = [], ...rest } = result.data;
await post(rest, flag("replace"));
const CHUNK = 250;
for (let i = 0; i < transactions.length; i += CHUNK) {
  await post({ transactions: transactions.slice(i, i + CHUNK) }, false);
  process.stdout.write(`\rTransactions: ${Math.min(i + CHUNK, transactions.length)}/${transactions.length}`);
}
console.log("\nDone.");
