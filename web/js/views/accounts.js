// Accounts tab: Assets / Liabilities / Total and grouped balances.

import { account, allTx, balances, currentPeriod, groups, periodRange, runningBalances, txRange } from "../store.js";
import { addMonths, esc, monthLabel, money } from "../format.js";
import { dayList, strip } from "../components.js";
import { monthSwitcher, pageHeader, pushPage, icons } from "../ui.js";
import { openEntry } from "./entry.js";
import { openAccountEditor, openAccountsAdmin } from "./more.js";

export function createAccounts() {
  const el = document.createElement("div");
  el.style.cssText = "display:flex;flex-direction:column;height:100%";
  el.innerHTML = `
    <header class="hdr"><div class="hdr-bar"><span></span><div class="hdr-title">Accounts</div>
      <div class="hdr-r"><button class="icon-btn" data-act="manage" aria-label="Edit accounts">${icons.pencil}</button><button class="icon-btn" data-act="add" aria-label="Add account">${icons.plus}</button></div></div>
      <div class="strip-wrap"></div></header>
    <div class="scroll"></div>`;

  function render() {
    const b = balances();
    el.querySelector(".strip-wrap").innerHTML = strip([["Assets", b.assets, "inc"], ["Liabilities", b.liabilities, "exp"], ["Total", b.total, ""]]);
    let html = "";
    for (const g of groups()) {
      const rows = b.rows.filter((r) => r.group_id === g.id && !r.hidden);
      if (!rows.length) continue;
      const sum = rows.reduce((s, r) => s + r.balance, 0);
      html += `<div class="acc-g"><span>${esc(g.name)}</span><span class="num ${sum < 0 ? "exp" : ""}">${money(sum)}</span></div>
        ${rows.map((r) => `<button class="acc-r" data-acc="${r.id}"><span>${esc(r.name)}${r.include_in_totals ? "" : ` <small class="muted">(excluded)</small>`}</span>
          <span class="b ${r.balance < 0 ? "exp" : "inc"}">${money(r.balance)}</span></button>`).join("")}`;
    }
    const hidden = b.rows.filter((r) => r.hidden);
    if (hidden.length) html += `<div class="acc-g"><span>Hidden</span><span></span></div>${hidden.map((r) => `<button class="acc-r" data-acc="${r.id}"><span class="muted">${esc(r.name)}</span><span class="b muted">${money(r.balance)}</span></button>`).join("")}`;
    el.querySelector(".scroll").innerHTML = html || `<div class="empty">No accounts</div>`;
  }

  el.addEventListener("click", (e) => {
    if (e.target.closest("[data-act=add]")) return openAccountEditor();
    if (e.target.closest("[data-act=manage]")) return openAccountsAdmin();
    const a = e.target.closest("[data-acc]");
    if (a) openAccount(a.dataset.acc);
  });

  return { el, render };
}

export function openAccount(id) {
  let ym = currentPeriod();
  return pushPage({
    tabs: true,
    html: `${pageHeader({ title: "", right: `<button class="icon-btn text" data-act="edit">Edit</button>` })}
      <div class="hdr" style="padding-top:0"><div style="display:flex;justify-content:center" class="sw"></div><div class="strip-wrap"></div></div>
      <div class="scroll"></div>
      <button class="fab" data-act="add" aria-label="Add transaction">${icons.plus}<span>Add</span></button>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      const a = e.target.closest("[data-act]");
      if (a?.dataset.act === "back") return p.close();
      if (a?.dataset.act === "edit") return openAccountEditor(account(id));
      if (a?.dataset.act === "add") return openEntry({ account: id, date: ym === currentPeriod() ? undefined : periodRange(ym).from });
      if (a?.dataset.act === "prev" || a?.dataset.act === "next") { ym = addMonths(ym, a.dataset.act === "prev" ? -1 : 1); p.render(); p.el.querySelector(".scroll").scrollTop = 0; return; }
      const row = e.target.closest("[data-tx]");
      if (row) return openEntry({ tx: allTx().find((t) => t.id === row.dataset.tx) });
      const day = e.target.closest("[data-add-day]");
      if (day) openEntry({ account: id, date: day.dataset.addDay });
    }),
    render: (p) => {
      const acc = account(id);
      if (!acc) return p.close();
      const bal = balances().rows.find((r) => r.id === id)?.balance ?? 0;
      p.el.querySelector(".hdr-title").textContent = acc.name;
      p.el.querySelector(".sw").innerHTML = monthSwitcher(monthLabel(ym));
      const { from, to } = periodRange(ym);
      const list = txRange(from, to, (t) => t.account_id === id || t.to_account_id === id);
      let dep = 0, wd = 0;
      for (const t of list) {
        if (t.type === "income" || (t.type === "transfer" && t.to_account_id === id)) dep += t.amount; else wd += t.amount;
      }
      p.el.querySelector(".strip-wrap").innerHTML = strip([["Deposit", dep, "inc"], ["Withdrawal", wd, "exp"], ["Balance", bal, bal < 0 ? "exp" : ""]]);
      p.el.querySelector(".scroll").innerHTML = dayList(list, { accountId: id, balances: runningBalances(id), addable: true, emptyText: `No transactions in ${monthLabel(ym)}` });
    },
  });
}
