// Stats tab: Stats (pie by category) / Budget / Note, like Money Manager.

import { allTx, budgetStatus, byCategory, catInfo, category, currentPeriod, periodRange, totals, txRange } from "../store.js";
import { addMonths, esc, monthLabel, money } from "../format.js";
import { budgetBar, dayList } from "../components.js";
import { icons, monthSwitcher, pageHeader, pushPage } from "../ui.js";
import { openEntry } from "./entry.js";
import { openBudgets } from "./more.js";
import { play } from "../motion.js";

/** Money Manager's pie colours, in slice order (Globals.f52644c in the APK). */
export const CHART = ["#fd6e63", "#ff9750", "#fed042", "#fee700", "#c1e746", "#72d36c", "#66e9db", "#72b8e3", "#a588d6", "#ed7ddc", "#e373a2"];
const colorOf = (i) => CHART[i % CHART.length];
const VIEWS = [["stats", "Stats"], ["budget", "Budget"], ["note", "Note"]];

export function createStats() {
  const st = { ym: currentPeriod(), year: false, type: "expense", view: "stats" };
  const el = document.createElement("div");
  el.style.cssText = "display:flex;flex-direction:column;height:100%";
  el.innerHTML = `
    <header class="hdr">
      <div class="hdr-bar stats-bar">
        <span></span>
        <div class="seg3">${VIEWS.map(([k, l]) => `<button data-view="${k}">${l}</button>`).join("")}</div>
        <div class="hdr-r"><button class="period-chip" data-act="period" aria-label="Month or year"></button></div>
      </div>
      <div class="sw"></div>
      <nav class="typetabs"></nav>
    </header>
    <div class="scroll"></div>`;
  const scroller = el.querySelector(".scroll");

  const range = () => st.year
    ? { from: periodRange(`${st.ym.slice(0, 4)}-01`).from, to: periodRange(`${st.ym.slice(0, 4)}-12`).to, label: st.ym.slice(0, 4) }
    : { ...periodRange(st.ym), label: monthLabel(st.ym) };

  /** motion: "next" / "prev" / "fade" after a user change; omitted for background refreshes. */
  function render(motion) {
    draw();
    if (!motion) return;
    play(scroller, motion);
    if (motion === "next" || motion === "prev") play(el.querySelector(".sw .lbl"), motion);
    play(scroller.querySelector(".pie-wrap svg"), "sweep");
  }

  function draw() {
    const r = range();
    el.querySelectorAll(".seg3 button").forEach((b) => b.classList.toggle("on", b.dataset.view === st.view));
    el.querySelector(".sw").innerHTML = monthSwitcher(r.label);
    el.querySelector("[data-act=period]").innerHTML = `${st.year ? "Y" : "M"}<span class="caret">▾</span>`;
    const list = txRange(r.from, r.to);
    const t = totals(list);
    const tabs = el.querySelector(".typetabs");
    tabs.classList.toggle("hidden", st.view === "budget");
    tabs.innerHTML = `
      <button class="${st.type === "income" ? "on" : ""}" data-type="income">Income ${money(t.income)}</button>
      <button class="${st.type === "expense" ? "on" : ""}" data-type="expense">Expenses ${money(t.expense)}</button>`;
    if (st.view === "budget") { scroller.innerHTML = budgetView(st.ym, txRange(periodRange(st.ym).from, periodRange(st.ym).to)); return; }
    if (st.view === "note") { scroller.innerHTML = noteView(list, st.type); return; }
    const rows = byCategory(list, st.type);
    if (!rows.length) { scroller.innerHTML = `<div class="empty">No data available.</div>`; return; }
    scroller.innerHTML = `<div class="stats-split">
      <div class="pie-wrap">${pie(rows)}</div>
      <div class="slist">${rows.map((row, i) => `
        <button class="srow" data-cat="${row.id ?? ""}">
          <span class="pct" style="background:${colorOf(i)}">${Math.round(row.percent)}%</span>
          <span class="nm">${esc(row.name)}</span>
          <span class="a">${money(row.total)}</span>
        </button>`).join("")}</div></div>`;
  }

  el.addEventListener("click", (e) => {
    const v = e.target.closest("[data-view]");
    if (v) { st.view = v.dataset.view; if (st.view === "budget") st.year = false; scroller.scrollTop = 0; render("fade"); return; }
    const tb = e.target.closest("[data-type]");
    if (tb) { st.type = tb.dataset.type; render("fade"); return; }
    const a = e.target.closest("[data-act]");
    if (a) {
      const act = a.dataset.act;
      if (act === "prev" || act === "next") st.ym = addMonths(st.ym, (act === "prev" ? -1 : 1) * (st.year ? 12 : 1));
      else if (act === "period") { if (st.view !== "budget") st.year = !st.year; }
      else if (act === "today") st.ym = currentPeriod();
      else if (act === "budgets") return openBudgets();
      render(act === "prev" || act === "next" ? act : "fade");
      return;
    }
    const slice = e.target.closest("[data-slice]");
    if (slice) {
      const row = el.querySelector(`.srow[data-cat="${slice.dataset.slice}"]`);
      if (row) { row.scrollIntoView({ behavior: "smooth", block: "center" }); row.classList.add("hl"); setTimeout(() => row.classList.remove("hl"), 900); }
      return;
    }
    const row = e.target.closest(".srow");
    if (row) { const r = range(); openCategory(row.dataset.cat || null, st.type, r.from, r.to, r.label); return; }
    const note = e.target.closest("[data-note]");
    if (note) { const r = range(); openNote(note.dataset.note, st.type, r.from, r.to); }
  });

  return { el, render };
}

function budgetView(ym, list) {
  const buds = budgetStatus(ym, list);
  return `<div class="bud-head"><span>Budget</span><button class="link" data-act="budgets">Budget Setting ›</button></div>
    ${buds.length ? buds.map(budgetBar).join("") : `<div class="empty">No budgets yet. Tap “Budget Setting”.</div>`}`;
}

/** Totals per note text, like Money Manager's Note tab. */
function noteView(list, type) {
  const m = new Map();
  for (const t of list) {
    if (t.type !== type) continue;
    const k = t.note.trim();
    const e = m.get(k) || { n: 0, v: 0 };
    e.n++; e.v += t.amount;
    m.set(k, e);
  }
  if (!m.size) return `<div class="empty">No data available.</div>`;
  return [...m.entries()].sort((a, b) => b[1].v - a[1].v).map(([k, e]) => `
    <button class="nrow" data-note="${esc(k)}"><span class="nm">${k ? esc(k) : `<span class="muted">(No note)</span>`}</span>
      <span class="cnt">${e.n}</span><span class="a ${type === "income" ? "inc" : "exp"}">${money(e.v)}</span></button>`).join("");
}

function openNote(note, type, from, to) {
  return pushPage({
    html: `${pageHeader({ title: esc(note || "(No note)") })}<div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      if (e.target.closest("[data-act=back]")) return p.close();
      const row = e.target.closest("[data-tx]");
      if (row) openEntry({ tx: allTx().find((t) => t.id === row.dataset.tx) });
    }),
    render: (p) => {
      const list = txRange(from, to, (t) => t.type === type && t.note.trim() === note);
      p.el.querySelector(".scroll").innerHTML = dayList(list);
    },
  });
}

/**
 * Pie with outside labels and leader lines (Money Manager draws it with Highcharts:
 * white slice borders, "<b>name</b><br>xx.x %" labels).
 */
function pie(rows) {
  const W = 440, H = 300, cx = W / 2, cy = H / 2 + 4, R = 88;
  const total = rows.reduce((s, r) => s + r.total, 0);
  if (!total) return "";
  // Slices run clockwise largest-first, so the small ones end up together at the tail.
  // Rotate so that tail is centred at 9 o'clock, where its labels have room to spread.
  const tail = rows.filter((r) => r.percent < 10).reduce((s, r) => s + (r.total / total) * Math.PI * 2, 0);
  let a0 = tail ? Math.PI + tail / 2 : -Math.PI / 2;
  const slices = rows.map((r, i) => {
    const a1 = a0 + (r.total / total) * Math.PI * 2;
    const s = { r, i, a0, a1, mid: (a0 + a1) / 2 };
    a0 = a1;
    return s;
  });
  const pt = (rad, a) => [cx + rad * Math.cos(a), cy + rad * Math.sin(a)];
  const f = (n) => n.toFixed(1);
  const paths = slices.length === 1
    ? `<circle cx="${cx}" cy="${cy}" r="${R}" fill="${colorOf(0)}" data-slice="${slices[0].r.id ?? ""}"/>`
    : slices.map((s) => {
      const [x0, y0] = pt(R, s.a0), [x1, y1] = pt(R, s.a1);
      const large = s.a1 - s.a0 > Math.PI ? 1 : 0;
      return `<path data-slice="${s.r.id ?? ""}" d="M${cx},${cy}L${f(x0)},${f(y0)}A${R},${R} 0 ${large},1 ${f(x1)},${f(y1)}Z" fill="${colorOf(s.i)}" stroke="#fff" stroke-width="1" stroke-linejoin="round"/>`;
    }).join("");

  // Labels: one column per side, pushed apart so they never overlap.
  const labeled = slices.filter((s) => s.r.percent >= 0.5).slice(0, 14);
  const GAP = 32, top = 16, bottom = H - 16;
  const sides = { L: [], R: [] };
  for (const s of labeled) {
    const right = Math.cos(s.mid) >= 0;
    const [, y] = pt(R + 22, s.mid);
    sides[right ? "R" : "L"].push({ s, y, right });
  }
  for (const col of Object.values(sides)) {
    col.sort((a, b) => a.y - b.y);
    for (let i = 0; i < col.length; i++) col[i].y = Math.max(col[i].y, i ? col[i - 1].y + GAP : top);
    for (let i = col.length - 1; i >= 0; i--) col[i].y = Math.min(col[i].y, i < col.length - 1 ? col[i + 1].y - GAP : bottom - 10);
  }
  const labels = [...sides.L, ...sides.R].map(({ s, y, right }) => {
    // Edge → short radial stub → elbow to the label column.
    const [ex, ey] = pt(R, s.mid), [kx, ky] = pt(R + 10, s.mid);
    const lx = right ? cx + R + 26 : cx - R - 26;
    const pct = `${s.r.percent.toFixed(1)} %`;
    const anchor = right ? "start" : "end";
    const tx = lx + (right ? 4 : -4);
    return `<polyline points="${f(ex)},${f(ey)} ${f(kx)},${f(ky)} ${f(lx)},${f(y + 4)}" fill="none" stroke="${colorOf(s.i)}" stroke-width="1"/>
      <text x="${f(tx)}" y="${f(y)}" text-anchor="${anchor}" class="pl-n">${esc(s.r.name.length > 12 ? s.r.name.slice(0, 11).trim() + "…" : s.r.name)}</text>
      <text x="${f(tx)}" y="${f(y + 15)}" text-anchor="${anchor}" class="pl-p">${pct}</text>`;
  }).join("");
  // The mask is a thick ring: animating its dash (styles.css, .sweep) wipes the pie in clockwise.
  const m = R / 2 + 1;
  const mask = `<mask id="pie-sweep"><circle class="sweep-c" cx="${cx}" cy="${cy}" r="${m}" fill="none" stroke="#fff" stroke-width="${2 * m + 2}"
    pathLength="100" stroke-dasharray="100 100" transform="rotate(-90 ${cx} ${cy})"/></mask>`;
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Category breakdown">${mask}<g mask="url(#pie-sweep)">${paths}</g><g class="pie-labels">${labels}</g></svg>`;
}

/** Transactions for one top-level category in a range. */
export function openCategory(catId, type, from, to, label) {
  const c = catId ? category(catId) : null;
  const title = c ? c.name : "Uncategorized";
  return pushPage({
    html: `${pageHeader({ title: esc(title) })}<div class="strip-wrap"></div><div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      if (e.target.closest("[data-act=back]")) return p.close();
      const row = e.target.closest("[data-tx]");
      if (row) openEntry({ tx: allTx().find((t) => t.id === row.dataset.tx) });
    }),
    render: (p) => {
      const list = txRange(from, to, (t) => t.type === type && (catInfo(t).topId ?? null) === (catId ?? null));
      const sum = list.reduce((s, t) => s + t.amount, 0);
      // Subcategory split, if any.
      const subs = new Map();
      for (const t of list) { const s = catInfo(t).sub || "(no subcategory)"; subs.set(s, (subs.get(s) || 0) + t.amount); }
      const subHtml = subs.size > 1 ? `<div class="card" style="margin:12px">${[...subs.entries()].sort((a, b) => b[1] - a[1])
        .map(([n, v]) => `<div class="row"><span class="lbl">${esc(n)}</span><span class="val">${money(v)} · ${Math.round((v / sum) * 100)}%</span></div>`).join("")}</div>` : "";
      p.el.querySelector(".strip-wrap").innerHTML = `<div class="strip" style="grid-template-columns:1fr 1fr">
        <div><small>${esc(label)}</small><b class="${type === "income" ? "inc" : "exp"}">${money(sum)}</b></div>
        <div><small>Transactions</small><b>${list.length}</b></div></div>`;
      p.el.querySelector(".scroll").innerHTML = (subHtml ? `<div style="background:var(--bg2);padding:1px 0">${subHtml}</div>` : "") + dayList(list);
    },
  });
}
