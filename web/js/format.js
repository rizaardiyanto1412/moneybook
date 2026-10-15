// Money and date helpers. Dates are handled as local 'YYYY-MM-DD' strings.

let currency = "USD";
let decimals = "";
let fmt, fmtNum;

// Cents exist on paper only (IDR, HUF, TWD…); same list as MoneybookCore's Money.fractionDigits.
const NO_CENTS = new Set(["JPY", "KRW", "VND", "IDR", "CLP", "ISK", "HUF", "TWD", "UGX", "PYG", "XAF", "XOF"]);

/** decimals: "" = automatic, or "0" / "1" / "2" from Configuration → Decimal Places. */
export function setCurrency(code, places = "") {
  if (code === currency && places === decimals && fmt) return;
  currency = code || "USD";
  decimals = places || "";
  // narrowSymbol: "Rp" instead of "IDR", "₩" instead of "KRW", like Money Manager.
  try { fmt = new Intl.NumberFormat(undefined, { style: "currency", currency, currencyDisplay: "narrowSymbol" }); }
  catch { currency = "USD"; fmt = new Intl.NumberFormat(undefined, { style: "currency", currency, currencyDisplay: "narrowSymbol" }); }
  const digits = decimals !== "" ? Number(decimals) : NO_CENTS.has(currency) ? 0 : fmt.resolvedOptions().maximumFractionDigits;
  fmt = new Intl.NumberFormat(undefined, { style: "currency", currency, currencyDisplay: "narrowSymbol", minimumFractionDigits: digits, maximumFractionDigits: digits });
  fmtNum = new Intl.NumberFormat(undefined, { minimumFractionDigits: digits, maximumFractionDigits: digits });
}
setCurrency("USD");

export const getCurrency = () => currency;
export const fractionDigits = () => fmt.resolvedOptions().maximumFractionDigits;
/** "$ 1,234.50" — Money Manager puts a space between the symbol and the number. */
export function money(n) {
  const parts = fmt.formatToParts(Math.round((n || 0) * 100) / 100);
  const i = parts.findIndex((p) => p.type === "currency");
  if (i >= 0 && parts[i + 1] && parts[i + 1].type !== "literal") parts.splice(i + 1, 0, { value: " " });
  return parts.map((p) => p.value).join("").replace(/\u00a0/g, " ").replace(/^-(\D+?) /, "$1 -");
}
/** "1,234.50" without the symbol (dense places like the calendar). */
export const num = (n) => fmtNum.format(Math.round((n || 0) * 100) / 100);
/** Compact number for tight calendar cells: 1,234 / 12.3k */
export function compact(n) {
  const a = Math.abs(n);
  if (a >= 100000) return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(n);
  if (a >= 1000) return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(n);
  return num(n);
}
export function currencySymbol(code = currency) {
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency: code, currencyDisplay: "narrowSymbol" }).formatToParts(0).find((p) => p.type === "currency")?.value || code;
  } catch { return code; }
}

const pad = (n) => String(n).padStart(2, "0");
export const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
export const parseYmd = (s) => { const [y, m, d] = s.slice(0, 10).split("-").map(Number); return new Date(y, m - 1, d, 12); };
export const today = () => ymd(new Date());
export function addDays(s, n) { const d = parseYmd(s); d.setDate(d.getDate() + n); return ymd(d); }

/** 'YYYY-MM' ± n months */
export function addMonths(ym, n) {
  const [y, m] = ym.split("-").map(Number);
  const d = new Date(y, m - 1 + n, 1, 12);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

/**
 * Inclusive date range for a month, honoring month_start_day (same rule as the server):
 * a start day < 20 names the period after the month it starts in, >= 20 after the month it ends in.
 */
export function monthPeriod(ym, startDay = 1) {
  const sd = Math.min(Math.max(Number(startDay) || 1, 1), 28);
  const [y, m] = ym.split("-").map(Number);
  const startMonth = sd >= 20 ? m - 2 : m - 1;
  return { from: ymd(new Date(y, startMonth, sd, 12)), to: ymd(new Date(y, startMonth + 1, sd - 1, 12)) };
}

/** The 'YYYY-MM' period that contains a given date. */
export function periodOf(dateStr, startDay = 1) {
  const sd = Math.min(Math.max(Number(startDay) || 1, 1), 28);
  const d = parseYmd(dateStr);
  const ym = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
  const startYm = d.getDate() >= sd ? ym : addMonths(ym, -1);
  return sd >= 20 ? addMonths(startYm, 1) : startYm;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DOW = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const monthName = (m) => MONTHS[m - 1];
export const dowName = (i) => DOW[i];
export const monthLabel = (ym) => { const [y, m] = ym.split("-").map(Number); return `${MONTHS[m - 1]} ${y}`; };
/** "Tue 13/10/2026"-style label for the entry form. */
export function longDate(s) {
  const d = parseYmd(s);
  return d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" });
}
export function shortRange(from, to) {
  const f = parseYmd(from), t = parseYmd(to);
  return `${f.getMonth() + 1}/${f.getDate()} ~ ${t.getMonth() + 1}/${t.getDate()}`;
}

/** Parse user-typed amounts like "1.234,50", "1,234.50", "12,5". */
export function parseAmount(s) {
  let v = String(s ?? "").trim().replace(/[^\d.,-]/g, "");
  if (!v) return NaN;
  const lastComma = v.lastIndexOf(","), lastDot = v.lastIndexOf(".");
  if (lastComma > -1 && lastDot > -1) {
    v = lastComma > lastDot ? v.replace(/\./g, "").replace(",", ".") : v.replace(/,/g, "");
  } else if (lastComma > -1) {
    const decimals = v.length - lastComma - 1;
    v = (v.split(",").length === 2 && decimals > 0 && decimals <= 2) ? v.replace(",", ".") : v.replace(/,/g, "");
  }
  return Number(v);
}

const ESC = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ESC[c]);
