import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { Blobs, Sql } from "./db.js";

// node:sqlite + filesystem implementations of the storage interfaces.

export function sqlite(file: string): Sql {
  const db = new DatabaseSync(file);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;");
  const p = (params: unknown[]) => params as any[];
  return {
    async all(query, ...params) {
      return db.prepare(query).all(...p(params)) as any[];
    },
    async first(query, ...params) {
      return (db.prepare(query).get(...p(params)) as any) ?? null;
    },
    async run(query, ...params) {
      db.prepare(query).run(...p(params));
    },
    async batch(statements) {
      db.exec("BEGIN");
      try {
        for (const s of statements) db.prepare(s.query).run(...p(s.params));
        db.exec("COMMIT");
      } catch (e) {
        db.exec("ROLLBACK");
        throw e;
      }
    },
  };
}

export function disk(root: string): Blobs {
  const resolve = (key: string) => {
    const full = path.resolve(root, key);
    if (!full.startsWith(root + path.sep)) throw new Error("Invalid key");
    return full;
  };
  return {
    async put(key, body, contentType) {
      const file = resolve(key);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, Buffer.from(body));
      fs.writeFileSync(file + ".type", contentType);
    },
    async get(key) {
      const file = resolve(key);
      if (!fs.existsSync(file)) return null;
      const contentType = fs.existsSync(file + ".type") ? fs.readFileSync(file + ".type", "utf8") : "application/octet-stream";
      const buf = fs.readFileSync(file);
      return { body: buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer, contentType };
    },
    async delete(key) {
      fs.rmSync(resolve(key), { force: true });
      fs.rmSync(resolve(key) + ".type", { force: true });
    },
  };
}
