// Runtime-neutral storage interfaces. The Worker backs them with D1 + R2,
// the VPS/Node entry with node:sqlite + the filesystem.

export interface Sql {
  all<T = Record<string, unknown>>(query: string, ...params: unknown[]): Promise<T[]>;
  first<T = Record<string, unknown>>(query: string, ...params: unknown[]): Promise<T | null>;
  run(query: string, ...params: unknown[]): Promise<void>;
  /** Runs statements atomically. */
  batch(statements: { query: string; params: unknown[] }[]): Promise<void>;
}

export interface Blob {
  body: ArrayBuffer | ReadableStream;
  contentType: string;
}

export interface Blobs {
  put(key: string, body: ArrayBuffer, contentType: string): Promise<void>;
  get(key: string): Promise<Blob | null>;
  delete(key: string): Promise<void>;
}

export interface Deps {
  sql: Sql;
  blobs: Blobs;
  apiToken: string;
}

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS account_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'asset',
  sort INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  name TEXT NOT NULL,
  initial_balance REAL NOT NULL DEFAULT 0,
  currency TEXT,
  include_in_totals INTEGER NOT NULL DEFAULT 1,
  hidden INTEGER NOT NULL DEFAULT 0,
  note TEXT NOT NULL DEFAULT '',
  sort INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS categories (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  name TEXT NOT NULL,
  icon TEXT NOT NULL DEFAULT '',
  parent_id TEXT,
  sort INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  date TEXT NOT NULL,
  amount REAL NOT NULL,
  account_id TEXT NOT NULL,
  to_account_id TEXT,
  category_id TEXT,
  note TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  receipt TEXT,
  source TEXT NOT NULL DEFAULT 'app',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date);
CREATE INDEX IF NOT EXISTS idx_tx_updated ON transactions(updated_at);
CREATE TABLE IF NOT EXISTS budgets (
  id TEXT PRIMARY KEY,
  category_id TEXT,
  month TEXT,
  amount REAL NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS blobs (
  key TEXT PRIMARY KEY,
  content_type TEXT NOT NULL,
  data BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS auth (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  label TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  last_used INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
`;

export function schemaStatements(): string[] {
  return SCHEMA.split(";").map((s) => s.trim()).filter(Boolean);
}
