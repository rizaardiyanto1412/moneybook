// Thin fetch wrapper for the same-origin Moneybook API.

const TOKEN_KEY = "mb.token";

export const auth = {
  get: () => localStorage.getItem(TOKEN_KEY) || "",
  set: (t) => localStorage.setItem(TOKEN_KEY, t),
  clear: () => localStorage.removeItem(TOKEN_KEY),
};

export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/** api("/api/x", {method, body, raw, contentType, token}) → parsed JSON. */
export async function api(path, opts = {}) {
  const token = opts.token ?? auth.get();
  const headers = { Authorization: `Bearer ${token}` };
  let body;
  if (opts.raw !== undefined) { body = opts.raw; headers["Content-Type"] = opts.contentType || "application/octet-stream"; }
  else if (opts.body !== undefined) { body = JSON.stringify(opts.body); headers["Content-Type"] = "application/json"; }
  let res;
  try {
    res = await fetch(path, { method: opts.method || "GET", headers, body, cache: "no-store" });
  } catch {
    throw new ApiError(0, "You're offline");
  }
  let data = null;
  try { data = await res.json(); } catch { /* empty body */ }
  if (!res.ok) {
    if (res.status === 401 && opts.token === undefined) window.dispatchEvent(new CustomEvent("mb:unauthorized"));
    throw new ApiError(res.status, data?.error || `Request failed (${res.status})`);
  }
  return data;
}

export const receiptUrl = (key) =>
  key ? `/api/receipts/${encodeURIComponent(key.replace(/^receipts\//, ""))}?token=${encodeURIComponent(auth.get())}` : "";
