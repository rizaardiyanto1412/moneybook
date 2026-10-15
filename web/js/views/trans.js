// Trans. tab: Daily / Calendar / Monthly / Summary.

import { balances, budgetStatus, currentPeriod, periodRange, txRange, totals, weekStart, allTx, catInfo } from "../store.js";
import { addDays, addMonths, compact, dowName, esc, monthLabel, monthName, money, parseYmd, shortRange, today } from "../format.js";
import { budgetBar, dayList, incExpTotal, txRow } from "../components.js";
import { icons, monthSwitcher, openSheet, pushPage, pageHeader } from "../ui.js";
import { openEntry } from "./entry.js";
import { openBudgets } from "./more.js";
import { countUp, play } from "../motion.js";

const MODES = [["daily", "Daily"], ["calendar", "Calendar"], ["weekly", "Weekly"], ["monthly", "Monthly"], ["summary", "Summary"]];

export function createTrans() {
  const st = { mode: sessionStorage.getItem("mb.transMode") || "daily", ym: currentPeriod(), year: Number(currentPeriod().slice(0, 4)) };
  const el = document.createElement("div");
  el.className = "tabview";
  el.style.cssText = "display:flex;flex-direction:column;height:100%";
  el.innerHTML = `
    <header class="hdr">
      <div class="hdr-bar">
        <button class="icon-btn hdr-l" data-act="search" aria-label="Search">${icons.search}</button>
        <div class="hdr-title">Transaction</div>
        <div class="hdr-r"><button class="icon-btn" data-act="search" aria-label="Filter">${icons.filter}</button></div>
      </div>
      <div class="sw"></div>
      <nav class="subtabs">${MODES.map(([k, l]) => `<button data-mode="${k}">${l}</button>`).join("")}</nav>
      <div class="strip-wrap"></div>
    </header>
    <div class="scroll"></div>`;
  const sw = el.querySelector(".sw");
  const stripWrap = el.querySelector(".strip-wrap");
  const scroller = el.querySelector(".scroll");

  /** motion: "next" / "prev" (month step) or "fade" (mode change); omitted for background refreshes. */
  function render(motion) {
    draw();
    countUp(stripWrap, !!motion);
    play(scroller, motion);
    if (motion === "next" || motion === "prev") play(sw.querySelector(".lbl"), motion);
  }

  function draw() {
    el.querySelectorAll(".subtabs button").forEach((b) => b.classList.toggle("on", b.dataset.mode === st.mode));
    const yearMode = st.mode === "monthly";
    sw.innerHTML = monthSwitcher(yearMode ? String(st.year) : monthLabel(st.ym));
    if (yearMode) {
      const list = txRange(periodRange(`${st.year}-01`).from, periodRange(`${st.year}-12`).to);
      stripWrap.innerHTML = incExpTotal(list);
      scroller.innerHTML = monthly(st.year);
      return;
    }
    const { from, to } = periodRange(st.ym);
    const list = txRange(from, to);
    stripWrap.innerHTML = incExpTotal(list);
    if (st.mode === "daily") scroller.innerHTML = dayList(list, { addable: true, emptyText: `No transactions in ${monthLabel(st.ym)}` });
    else if (st.mode === "calendar") scroller.innerHTML = calendar(from, to, list);
    else if (st.mode === "weekly") scroller.innerHTML = weekly(from, to, list);
    else scroller.innerHTML = summary(st.ym, list);
  }

  el.addEventListener("click", (e) => {
    const m = e.target.closest("[data-mode]");
    if (m) {
      st.mode = m.dataset.mode;
      sessionStorage.setItem("mb.transMode", st.mode);
      if (st.mode === "monthly") st.year = Number(st.ym.slice(0, 4));
      scroller.scrollTop = 0;
      render("fade");
      return;
    }
    const a = e.target.closest("[data-act]");
    if (a) {
      const act = a.dataset.act;
      if (act === "prev" || act === "next") {
        const d = act === "prev" ? -1 : 1;
        if (st.mode === "monthly") st.year += d; else st.ym = addMonths(st.ym, d);
        scroller.scrollTop = 0;
        render(act);
      } else if (act === "today") { st.ym = currentPeriod(); st.year = Number(st.ym.slice(0, 4)); render("fade"); }
      else if (act === "search") openSearch();
      else if (act === "budgets") openBudgets();
      return;
    }
    const tx = e.target.closest("[data-tx]");
    if (tx) { openEntry({ tx: allTxById(tx.dataset.tx) }); return; }
    const add = e.target.closest("[data-add-day]");
    if (add) { openEntry({ date: add.dataset.addDay }); return; }
    const day = e.target.closest("[data-day]");
    if (day) { openDay(day.dataset.day); return; }
    const mon = e.target.closest("[data-ym]");
    const wk = e.target.closest("[data-week]");
    if (wk) { openWeek(wk.dataset.week); return; }
    if (mon) { st.ym = mon.dataset.ym; st.mode = "daily"; sessionStorage.setItem("mb.transMode", "daily"); scroller.scrollTop = 0; render("fade"); }
  });

  // Horizontal swipe on the list switches months, like the native app.
  let sx = 0, sy = 0;
  scroller.addEventListener("touchstart", (e) => { sx = e.touches[0].clientX; sy = e.touches[0].clientY; }, { passive: true });
  scroller.addEventListener("touchend", (e) => {
    const dx = e.changedTouches[0].clientX - sx, dy = e.changedTouches[0].clientY - sy;
    if (Math.abs(dx) > 70 && Math.abs(dx) > Math.abs(dy) * 1.8) el.querySelector(`[data-act=${dx < 0 ? "next" : "prev"}]`).click();
  }, { passive: true });

  return {
    el, render, fab: true,
    newEntryDate: () => {
      const { from, to } = periodRange(st.ym);
      const t = today();
      return t >= from && t <= to ? t : from;
    },
  };
}

const allTxById = (id) => allTx().find((t) => t.id === id);

function calendar(from, to, list) {
  const ws = weekStart();
  const byDay = new Map();
  for (const t of list) {
    const d = t.date.slice(0, 10);
    const e = byDay.get(d) || { inc: 0, exp: 0 };
    if (t.type === "income") e.inc += t.amount; else if (t.type === "expense") e.exp += t.amount;
    byDay.set(d, e);
  }
  let start = from;
  while (parseYmd(start).getDay() !== ws) start = addDays(start, -1);
  let end = to;
  while (parseYmd(end).getDay() !== (ws + 6) % 7) end = addDays(end, 1);
  const t0 = today();
  let html = `<div class="cal">`;
  for (let i = 0; i < 7; i++) { const d = (ws + i) % 7; html += `<div class="wd ${d === 0 ? "sun" : d === 6 ? "sat" : ""}">${dowName(d)}</div>`; }
  for (let d = start; d <= end; d = addDays(d, 1)) {
    const dt = parseYmd(d), dow = dt.getDay();
    const v = byDay.get(d);
    const out = d < from || d > to;
    html += `<div class="cell${out ? " out" : ""}${dow === 0 ? " sun" : dow === 6 ? " sat" : ""}${d === t0 ? " today" : ""}" data-day="${d}" role="button" aria-label="${d}">
      <span class="d">${dt.getDate() === 1 ? `${String(dt.getMonth() + 1).padStart(2, "0")}/01` : dt.getDate()}</span>
      ${v?.inc ? `<span class="v inc">${compact(v.inc)}</span>` : ""}
      ${v?.exp ? `<span class="v exp">${compact(v.exp)}</span>` : ""}
      ${v && v.inc && v.exp ? `<span class="v t">${compact(v.inc - v.exp)}</span>` : ""}
    </div>`;
  }
  return html + `</div>`;
}

function weekly(from, to, list) {
  const ws = weekStart();
  let start = from;
  while (parseYmd(start).getDay() !== ws) start = addDays(start, -1);
  const t0 = today();
  const rows = [];
  for (let w = start; w <= to; w = addDays(w, 7)) {
    const we = addDays(w, 6);
    const t = totals(list.filter((x) => { const d = x.date.slice(0, 10); return d >= w && d <= we; }));
    const md = (s) => `${s.slice(5, 7)}/${s.slice(8, 10)}`;
    rows.push(`<div class="wrow${t0 >= w && t0 <= we ? " cur" : ""}" data-week="${w}" role="button">
      <span class="rng">${md(w)} ~ ${md(we)}</span>
      <span class="amt inc">${money(t.income)}</span>
      <span class="amt exp">${money(t.expense)}</span>
      <span class="amt tot">${money(t.total)}</span>
    </div>`);
  }
  return rows.reverse().join("");
}

function openWeek(w) {
  const we = addDays(w, 6);
  const list = txRange(w, we);
  const page = pushPage({
    html: `${pageHeader({ title: `${shortRange(w, we)}` })}<div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      if (e.target.closest("[data-act=back]")) { p.close(); return; }
      const row = e.target.closest("[data-tx]");
      if (row) openEntry({ tx: allTxById(row.dataset.tx) });
    }),
    render: (p) => { p.el.querySelector(".scroll").innerHTML = incExpTotal(list) + dayList(txRange(w, we), { emptyText: "Nothing this week" }); },
  });
  return page;
}

function openDay(d) {
  const list = txRange(d, d);
  const t = totals(list);
  const dt = parseYmd(d);
  openSheet({
    title: dt.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" }),
    right: `<button class="icon-btn text" data-act="add" aria-label="Add">${icons.plus}</button>`,
    tall: list.length > 4,
    html: `<div class="daysheet-tot"><span class="inc">${money(t.income)}</span><span class="exp">${money(t.expense)}</span><span>${money(t.total)}</span></div>
      ${list.length ? `<section class="day">${list.map((x) => txRow(x)).join("")}</section>` : `<div class="empty" style="padding:36px">Nothing on this day</div>`}`,
    onMount: (el, sh) => el.addEventListener("click", (e) => {
      if (e.target.closest("[data-act=add]")) { sh.close(); openEntry({ date: d }); return; }
      const row = e.target.closest("[data-tx]");
      if (row) { sh.close(); openEntry({ tx: allTxById(row.dataset.tx) }); }
    }),
  });
}

function monthly(year) {
  const cur = currentPeriod();
  let html = "";
  for (let m = 12; m >= 1; m--) {
    const ym = `${year}-${String(m).padStart(2, "0")}`;
    const { from, to } = periodRange(ym);
    const t = totals(txRange(from, to));
    if (ym > cur && !t.income && !t.expense) continue;
    html += `<div class="mrow${ym === cur ? " cur" : ""}" data-ym="${ym}" role="button">
      <div><b>${monthName(m)}</b><small>${shortRange(from, to)}</small></div>
      <div class="vals"><div class="inc">${money(t.income)}</div><div class="exp">${money(t.expense)}</div><div class="t">${money(t.total)}</div></div>
    </div>`;
  }
  return html || `<div class="empty">No data for ${year}</div>`;
}

function summary(ym, list) {
  const t = totals(list);
  const buds = budgetStatus(ym, list);
  // Expense by account.
  const byAcc = new Map();
  for (const x of list) if (x.type === "expense") byAcc.set(x.account_id, (byAcc.get(x.account_id) || 0) + x.amount);
  const accRows = [...byAcc.entries()].sort((a, b) => b[1] - a[1]);
  const names = new Map(balances().rows.map((r) => [r.id, r.name]));
  const days = new Set(list.map((x) => x.date.slice(0, 10))).size;
  const { from, to } = periodRange(ym);
  const span = Math.max(1, Math.min(Math.round((parseYmd(today() < to ? (today() < from ? from : today()) : to) - parseYmd(from)) / 864e5) + 1, 31));
  // Top expense categories.
  const cats = new Map();
  for (const x of list) if (x.type === "expense") { const i = catInfo(x); cats.set(i.name, { icon: i.icon, v: (cats.get(i.name)?.v || 0) + x.amount }); }
  const topCats = [...cats.entries()].sort((a, b) => b[1].v - a[1].v).slice(0, 3);
  return `<div class="grouped">
    <div class="card">
      <div class="card-h">${esc(monthLabel(ym))}<span class="muted" style="font-weight:400;font-size:13px">${shortRange(from, to)}</span></div>
      <div class="row"><span class="lbl">Transactions</span><span class="val">${list.length} on ${days} day${days === 1 ? "" : "s"}</span></div>
      <div class="row"><span class="lbl">Savings rate</span><span class="val">${t.income ? Math.round((t.total / t.income) * 100) + "%" : "—"}</span></div>
      <div class="row"><span class="lbl">Avg. spending / day</span><span class="val">${money(t.expense / span)}</span></div>
    </div>
    <div class="card">
      <div class="card-h">Budget<button class="link" data-act="budgets">Budget setting</button></div>
      ${buds.length ? buds.map(budgetBar).join("") : `<div class="row"><span class="lbl muted">No budgets yet. Tap “Budget setting”.</span></div>`}
    </div>
    ${accRows.length ? `<div class="card"><div class="card-h">Exp. by account</div>
      ${accRows.map(([id, v]) => `<div class="row"><span class="lbl">${esc(names.get(id) || "?")}</span><span class="val exp">${money(v)}</span></div>`).join("")}</div>` : ""}
    ${topCats.length ? `<div class="card"><div class="card-h">Top categories</div>
      ${topCats.map(([n, c]) => `<div class="row"><span class="em">${esc(c.icon)}</span><span class="lbl">${esc(n)}</span><span class="val">${money(c.v)}</span></div>`).join("")}</div>` : ""}
  </div>`;
}

function openSearch() {
  let q = "";
  const page = pushPage({
    html: `${pageHeader({ title: "Search" })}
      <div style="padding:0 0 4px;background:var(--chrome)"><input class="input search-in" type="search" placeholder="Note, description, category, amount" style="width:calc(100% - 28px)"></div>
      <div class="scroll"></div>`,
    onMount: (el, p) => {
      const input = el.querySelector("input");
      input.addEventListener("input", () => { q = input.value.trim().toLowerCase(); p.render(); });
      setTimeout(() => input.focus(), 350);
      el.addEventListener("click", (e) => {
        if (e.target.closest("[data-act=back]")) p.close();
        const row = e.target.closest("[data-tx]");
        if (row) openEntry({ tx: allTxById(row.dataset.tx) });
      });
    },
    render: (p) => {
      const out = p.el.querySelector(".scroll");
      if (!q) { out.innerHTML = `<div class="empty"><span class="big">🔎</span>Search all transactions</div>`; return; }
      const res = allTx().filter((t) => {
        const i = catInfo(t);
        return `${t.note} ${t.description} ${i.name} ${i.sub} ${t.amount}`.toLowerCase().includes(q);
      }).slice(0, 300);
      out.innerHTML = (res.length ? incExpTotal(res) : "") + dayList(res, { emptyText: "No matches" });
    },
  });
  return page;
}

