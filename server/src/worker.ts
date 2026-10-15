import { createApp } from "./app.js";
import type { Blobs, Deps, Sql } from "./db.js";
import { ApiError } from "./service.js";

// Cloudflare Workers entry: D1 for data, static assets for the web app, and receipt
// photos in R2 when the RECEIPTS bucket is bound (otherwise in a D1 table).

interface Env {
  DB: D1Database;
  RECEIPTS?: R2Bucket;
  API_TOKEN: string;
}

function d1(db: D1Database): Sql {
  return {
    async all(query, ...params) {
      return (await db.prepare(query).bind(...params).all()).results as any[];
    },
    async first(query, ...params) {
      return (await db.prepare(query).bind(...params).first()) as any;
    },
    async run(query, ...params) {
      await db.prepare(query).bind(...params).run();
    },
    async batch(statements) {
      if (statements.length) await db.batch(statements.map((s) => db.prepare(s.query).bind(...s.params)));
    },
  };
}

function r2(bucket: R2Bucket): Blobs {
  return {
    async put(key, body, contentType) {
      await bucket.put(key, body, { httpMetadata: { contentType } });
    },
    async get(key) {
      const obj = await bucket.get(key);
      return obj ? { body: obj.body, contentType: obj.httpMetadata?.contentType ?? "application/octet-stream" } : null;
    },
    async delete(key) {
      await bucket.delete(key);
    },
  };
}

/** Receipts stored in D1 itself, for accounts without R2 enabled (rows are capped at 2 MB). */
function d1Blobs(db: D1Database): Blobs {
  return {
    async put(key, body, contentType) {
      if (body.byteLength > 1_900_000) throw new ApiError(413, "Receipt too large for D1 storage (max ~1.9 MB); enable R2 or shrink the photo");
      await db.prepare("INSERT OR REPLACE INTO blobs (key, content_type, data) VALUES (?,?,?)").bind(key, contentType, body).run();
    },
    async get(key) {
      const row = await db.prepare("SELECT content_type, data FROM blobs WHERE key=?").bind(key).first<{ content_type: string; data: number[] | ArrayBuffer }>();
      if (!row) return null;
      const data = row.data instanceof ArrayBuffer ? row.data : new Uint8Array(row.data).buffer;
      return { body: data, contentType: row.content_type };
    },
    async delete(key) {
      await db.prepare("DELETE FROM blobs WHERE key=?").bind(key).run();
    },
  };
}

// Keep one Sql wrapper per isolate so migrate() only runs once.
let cached: { db: D1Database; deps: Deps } | undefined;

const app = createApp((c) => {
  const env = c.env as Env;
  if (!cached || cached.db !== env.DB) {
    cached = { db: env.DB, deps: { sql: d1(env.DB), blobs: env.RECEIPTS ? r2(env.RECEIPTS) : d1Blobs(env.DB), apiToken: env.API_TOKEN } };
  }
  return cached.deps;
});

export default app;
