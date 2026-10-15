// Shared rendering: day-grouped transaction lists and the Income/Exp/Total strip.

import { account, catInfo, totals } from "./store.js";
import { dowName, esc, money, num, parseYmd } from "./format.js";

const recentlyAdded = new Set();
/** Mark transaction ids to flash once in lists (e.g. ones the AI just added). */
export function flashIds(ids) { ids.forEach((id) => recentlyAdded.add(id)); setTimeout(() => ids.forEach((id) => recentlyAdded.delete(id)), 2500); }

export function txRow(t, { accountId, balances } = {}) {
  const info = catInfo(t);
  const acc = account(t.account_id)?.name ?? t.account_name ?? "?";
  let cls = t.type === "income" ? "inc" : t.type === "expense" ? "exp" : "xfer";
  let accLine = esc(acc);
  let amount = money(t.amount);
  if (t.type === "transfer") {
    const to = account(t.to_account_id)?.name ?? t.to_account_name ?? "?";
    accLine = `${esc(acc)} → ${esc(to)}`;
    if (accountId) {
      const incoming = t.to_account_id === accountId;
      cls = incoming ? "inc" : "exp";
    }
  }
  // Like Money Manager: category column (name over sub-category), then note over account.
  // A transfer without a note shows its "From → To" line as the title.
  const catName = t.type === "transfer" ? "Transfer" : info.name;
  const title = t.note ? esc(t.note) : t.type === "transfer" ? accLine : "";
  const second = t.note || t.type !== "transfer" ? accLine : "";
  return `<div class="tx${recentlyAdded.has(t.id) ? " new" : ""}" data-tx="${t.id}" role="button">
    <div class="tx-cat"><span>${esc(catName)}</span>${info.sub && t.type !== "transfer" ? `<span>${esc(info.sub)}</span>` : ""}</div>
    <div class="tx-main">
      ${title ? `<div class="tx-note">${title}${t.source === "ai" ? `<span class="ai" title="Added by AI">✦</span>` : ""}${t.receipt ? `<span class="clip" title="Receipt">📎</span>` : ""}</div>` : ""}
      ${second ? `<div class="tx-acc">${second}</div>` : ""}
    </div>
    <div class="tx-amt ${cls}">${amount}${balances?.has(t.id) ? `<small>${num(balances.get(t.id))}</small>` : ""}</div>
  </div>`;
}

/** Group a (date-desc) list by day with Money Manager style headers. */
export function dayList(list, opts = {}) {
  if (!list.length) return `<div class="empty"><span class="big">🧾</span>${esc(opts.emptyText || "No transactions")}</div>`;
  const days = new Map();
  for (const t of list) {
    const d = t.date.slice(0, 10);
    if (!days.has(d)) days.set(d, []);
    days.get(d).push(t);
  }
  let html = "";
  for (const [d, rows] of days) {
    const dt = parseYmd(d);
    const dow = dt.getDay();
    let { income, expense } = totals(rows);
    if (opts.accountId) {
      // In an account's ledger, transfers count as money in / out.
      for (const t of rows) if (t.type === "transfer") { if (t.to_account_id === opts.accountId) income += t.amount; else expense += t.amount; }
    }
    html += `<section class="day">
      <div class="day-h"${opts.addable ? ` data-add-day="${d}" role="button" aria-label="Add on ${d}"` : ""}>
        <span class="dnum">${dt.getDate()}</span>
        <span class="dmeta"><span class="dow ${dow === 0 ? "sun" : dow === 6 ? "sat" : ""}">${dowName(dow)}</span></span>
        <span class="amt inc">${money(income)}</span>
        <span class="amt exp">${money(expense)}</span>
      </div>
      ${rows.map((t) => txRow(t, opts)).join("")}
    </section>`;
  }
  return html;
}

export function strip(items) {
  return `<div class="strip">${items.map(([label, value, cls]) => `<div><small>${esc(label)}</small><b class="${cls || ""}" data-n="${value}">${num(value)}</b></div>`).join("")}</div>`;
}

export const incExpTotal = (list) => {
  const t = totals(list);
  return strip([["Income", t.income, "inc"], ["Exp.", t.expense, "exp"], ["Total", t.total, ""]]);
};

/** One budget line: name, spent / budget, bar, % and remaining. */
export function budgetBar(b) {
  const pct = Math.min(b.percent, 100);
  const cls = b.percent > 100 ? "over" : b.percent > 85 ? "warn" : "";
  return `<div class="bud">
    <div class="bud-top"><span>${esc(b.isTotal ? "Total budget" : b.name)}</span><span class="r">${money(b.spent)} / ${money(b.budget)}</span></div>
    <div class="bar"><i class="${cls}" style="width:${pct}%"></i></div>
    <div class="bud-bot"><span>${Math.round(b.percent)}%</span><span class="${b.remaining < 0 ? "exp" : ""}">${b.remaining < 0 ? "Over by " + money(-b.remaining) : money(b.remaining) + " left"}</span></div>
  </div>`;
}
