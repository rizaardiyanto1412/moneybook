// Money Manager backup import, done in the browser: the .mmbak (a raw SQLite file) is opened with sql.js,
// converted by the same code the CLI importer uses (mmbak.js, built from server/scripts/mmbak.ts)
// and uploaded to /api/import in chunks.

import { api } from "./api.js";
import { convert } from "./mmbak.js";

let sqlJs = null;

/** Loads sql.js (≈700 KB) the first time an import is started. */
function loadSqlJs() {
  sqlJs ??= new Promise((resolve, reject) => {
    const s = document.createElement("script");
    s.src = "/vendor/sqljs/sql-wasm.js";
    s.onload = () => window.initSqlJs({ locateFile: (f) => `/vendor/sqljs/${f}` }).then(resolve, reject);
    s.onerror = () => reject(new Error("Couldn't load the SQLite reader. Check your connection."));
    document.head.appendChild(s);
  }).catch((e) => { sqlJs = null; throw e; });
  return sqlJs;
}

async function gunzip(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** node:sqlite-style prepare().all()/get() on top of a sql.js database. */
function adapt(db) {
  return {
    prepare(query) {
      const rows = () => {
        const out = [];
        const st = db.prepare(query);
        try { while (st.step()) out.push(st.getAsObject()); } finally { st.free(); }
        return out;
      };
      return { all: rows, get: () => rows()[0] };
    },
  };
}

const SQLITE_MAGIC = "SQLite format 3";

/** Reads a backup file → {flavor, data, warnings, counts}. Accepts .mmbak/.sqlite and gzip'd copies. */
export async function readBackup(file, timezone) {
  let bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) bytes = await gunzip(bytes);
  if (new TextDecoder().decode(bytes.subarray(0, SQLITE_MAGIC.length)) !== SQLITE_MAGIC) {
    throw new Error("This isn't a Money Manager backup. Export one from Money Manager → Backup → Export.");
  }
  const SQL = await loadSqlJs();
  const db = new SQL.Database(bytes);
  try {
    const result = convert(adapt(db), timezone);
    const counts = Object.fromEntries(Object.entries(result.data).filter(([k]) => k !== "settings").map(([k, v]) => [k, v.length]));
    return { ...result, counts };
  } finally {
    db.close();
  }
}

const CHUNK = 250; // keeps each request under D1's statement-size limit

/** Uploads converted data. replace=true soft-deletes everything currently in Moneybook first. */
export async function uploadBackup(data, { replace, onProgress }) {
  const { transactions = [], ...rest } = data;
  await api(`/api/import${replace ? "?replace=1" : ""}`, { method: "POST", body: rest });
  for (let i = 0; i < transactions.length; i += CHUNK) {
    await api("/api/import", { method: "POST", body: { transactions: transactions.slice(i, i + CHUNK) } });
    onProgress?.(Math.min(i + CHUNK, transactions.length), transactions.length);
  }
}
