// Email + password sign-in for the web app. Single user: one login, many device sessions.
// The API token stays the master key (for AI/MCP clients and for setting the first password).
// Uses WebCrypto only, so the same code runs on Workers and Node.

import type { Sql } from "./db.js";
import { ApiError } from "./service.js";

const ITERATIONS = 100_000;               // Workers' PBKDF2 maximum
const SESSION_MS = 365 * 24 * 3600_000;   // sliding: renewed when used
const RENEW_AFTER_MS = 24 * 3600_000;
const MAX_FAILS = 5;
const FAIL_WINDOW_MS = 15 * 60_000;

const enc = new TextEncoder();
const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const b64url = (bytes: Uint8Array) => b64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function pbkdf2(password: string, salt: Uint8Array<ArrayBuffer>, iterations: number) {
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations }, key, 256));
}

async function sha256(s: string) {
  return b64(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s))));
}

function sameBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

const getKey = async (sql: Sql, key: string) =>
  (await sql.first<{ value: string }>("SELECT value FROM auth WHERE key = ?", key))?.value ?? null;
const setKey = (sql: Sql, key: string, value: string) =>
  sql.run("INSERT INTO auth (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value);

const normEmail = (e: unknown) => String(e ?? "").trim().toLowerCase();

export async function status(sql: Sql) {
  const email = await getKey(sql, "email");
  return { hasPassword: !!email, email };
}

/** Set or change the login. `master` = caller used the API token, so the current password isn't needed. */
export async function setPassword(sql: Sql, body: Record<string, unknown>, master: boolean, keepSession?: string) {
  const email = normEmail(body.email);
  const password = String(body.password ?? "");
  if (!/^[^\s@]+@[^\s@]+$/.test(email)) throw new ApiError(400, "Enter a valid email");
  if (password.length < 8) throw new ApiError(400, "Password must be at least 8 characters");
  if ((await status(sql)).hasPassword && !master && !(await checkPassword(sql, String(body.current ?? "")))) {
    throw new ApiError(403, "Current password is wrong");
  }
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(password, salt, ITERATIONS);
  await setKey(sql, "email", email);
  await setKey(sql, "password", `pbkdf2-sha256$${ITERATIONS}$${b64(salt)}$${b64(hash)}`);
  // A new password signs out every other device.
  if (keepSession) await sql.run("DELETE FROM sessions WHERE token_hash != ?", await sha256(keepSession));
  else await sql.run("DELETE FROM sessions");
  return status(sql);
}

async function checkPassword(sql: Sql, password: string) {
  const stored = await getKey(sql, "password");
  if (!stored) return false;
  const [, iter, salt, hash] = stored.split("$");
  return sameBytes(await pbkdf2(password, unb64(salt), Number(iter)), unb64(hash));
}

export async function login(sql: Sql, body: Record<string, unknown>, label: string) {
  const now = Date.now();
  const fails = JSON.parse((await getKey(sql, "fails")) ?? '{"n":0,"since":0}') as { n: number; since: number };
  if (fails.n >= MAX_FAILS && now - fails.since < FAIL_WINDOW_MS) {
    const mins = Math.ceil((FAIL_WINDOW_MS - (now - fails.since)) / 60_000);
    throw new ApiError(429, `Too many attempts. Try again in ${mins} minute${mins > 1 ? "s" : ""}.`);
  }
  const ok = normEmail(body.email) === (await getKey(sql, "email")) && (await checkPassword(sql, String(body.password ?? "")));
  if (!ok) {
    const fresh = now - fails.since >= FAIL_WINDOW_MS;
    await setKey(sql, "fails", JSON.stringify({ n: fresh ? 1 : fails.n + 1, since: fresh ? now : fails.since }));
    throw new ApiError(401, "Wrong email or password");
  }
  await setKey(sql, "fails", '{"n":0,"since":0}');
  const session = "s_" + b64url(crypto.getRandomValues(new Uint8Array(32)));
  await sql.run("INSERT INTO sessions (token_hash, label, created_at, last_used, expires_at) VALUES (?,?,?,?,?)",
    await sha256(session), label.slice(0, 120), now, now, now + SESSION_MS);
  return { session };
}

/** True when `token` is a live session; renews it at most once a day. */
export async function checkSession(sql: Sql, token: string) {
  if (!token.startsWith("s_")) return false;
  const hash = await sha256(token);
  const row = await sql.first<{ last_used: number; expires_at: number }>("SELECT last_used, expires_at FROM sessions WHERE token_hash = ?", hash);
  const now = Date.now();
  if (!row || row.expires_at < now) return false;
  if (now - row.last_used > RENEW_AFTER_MS) {
    await sql.run("UPDATE sessions SET last_used = ?, expires_at = ? WHERE token_hash = ?", now, now + SESSION_MS, hash);
  }
  return true;
}

export async function logout(sql: Sql, token: string) {
  await sql.run("DELETE FROM sessions WHERE token_hash = ?", await sha256(token));
}

export async function logoutAll(sql: Sql) {
  await sql.run("DELETE FROM sessions");
}
