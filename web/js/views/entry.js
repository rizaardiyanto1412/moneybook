// Full-screen transaction form (new + edit), Money Manager style.

import { api, receiptUrl } from "../api.js";
import { accounts, account, categoryTree, category, db, groups, sync, upsertLocal, removeLocal } from "../store.js";
import { dowName, esc, fractionDigits, hm, parseAmount, parseYmd, today, currencySymbol, getCurrency } from "../format.js";
import { confirmSheet, icons, openSheet, pushPage, toast } from "../ui.js";
import { openAccountsAdmin, openCategories } from "./more.js";

function openSettingsFor(kind) {
  if (kind === "category") openCategories(document.querySelector(".page.entry")?.dataset.type || "expense");
  else openAccountsAdmin();
}

const TYPE_LABEL = { income: "Income", expense: "Expense", transfer: "Transfer" };
const TYPE_COLOR = { income: "var(--inc)", expense: "var(--exp)", transfer: "var(--xfer)" };
const LAST_ACC = "mb.lastAccount";

/** openEntry({tx}) edits; openEntry({date, type, account}) creates. */
export function openEntry({ tx, date, type, account: accountId } = {}) {
  const now = new Date();
  const s = tx ? {
    id: tx.id, type: tx.type, date: tx.date.slice(0, 10), time: tx.date.slice(11, 16) || "12:00",
    account_id: tx.account_id, to_account_id: tx.to_account_id || "", category_id: tx.category_id || "",
    amount: String(tx.amount), note: tx.note || "", description: tx.description || "", receipt: tx.receipt || null,
  } : {
    type: type || "expense", date: date || today(), time: hm(now),
    account_id: accountId || defaultAccount(), to_account_id: "", category_id: "", amount: "", note: "", description: "", receipt: null,
  };
  s.photo = null; s.photoUrl = ""; s.removePhoto = false; s.saving = false;
  s.panel = null; s.openParent = null;

  const page = pushPage({
    kind: "modal",
    className: "entry",
    html: `<header class="hdr"><div class="hdr-bar">
        <button class="icon-btn hdr-l back-lbl" data-act="back" aria-label="Back">${icons.left}<span>Trans.</span></button>
        <div class="hdr-title"></div><div class="hdr-r"></div></div></header>
      <div class="typeseg">${["income", "expense", "transfer"].map((t) => `<button data-type="${t}">${TYPE_LABEL[t]}</button>`).join("")}</div>
      <div class="scroll"><form class="form" autocomplete="off" novalidate></form><div class="form-actions"></div></div>
      <div class="ipanel" hidden><div class="ipanel-h"><span class="t"></span><span class="r"></span></div><div class="ipanel-b"></div></div>`,
    onMount: (el, p) => { p.repaint = mount(el, p, s, !!tx); },
    onClose: () => { if (s.photoUrl) URL.revokeObjectURL(s.photoUrl); s.unmount?.(); },
  });
  page.state = s;
  return page;
}

function defaultAccount() {
  const last = localStorage.getItem(LAST_ACC);
  if (last && db.accounts.has(last)) return last;
  if (db.settings.default_account_id && db.accounts.has(db.settings.default_account_id)) return db.settings.default_account_id;
  return accounts()[0]?.id || "";
}

function mount(el, page, s, editing) {
  const form = el.querySelector("form");
  const actions = el.querySelector(".form-actions");

  const paint = () => {
    el.style.setProperty("--tc", TYPE_COLOR[s.type]);
    el.dataset.type = s.type;
    el.querySelector(".hdr-title").textContent = TYPE_LABEL[s.type];
    el.querySelectorAll(".typeseg button").forEach((b) => b.classList.toggle("on", b.dataset.type === s.type));
    form.innerHTML = formHtml(s);
    actions.classList.toggle("three", editing);
    actions.innerHTML = editing
      ? `<button class="btn primary wide" data-act="save">Save</button>
         <button class="btn ghost" data-act="delete">${icons.trash}Delete</button>
         <button class="btn ghost" data-act="copy">${icons.copy}Copy</button>`
      : `<button class="btn primary" data-act="save">Save</button><button class="btn ghost" data-act="continue">Continue</button>`;
    autosize(form.querySelector("textarea"));
    if (s.panel) form.querySelector(`[data-act=pick-${s.panel}]`)?.classList.add("focus");
  };
  paint();

  el.querySelector(".typeseg").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-type]");
    if (!b || b.dataset.type === s.type) return;
    const was = s.type;
    s.type = b.dataset.type;
    // Categories are typed; keep only if still valid.
    if (s.category_id && category(s.category_id)?.type !== s.type) s.category_id = "";
    if (s.type === "transfer" && was !== "transfer") s.category_id = "";
    paint();
    if (s.panel === "category" && s.type === "transfer") showPanel("to");
    else if (s.panel === "to" && s.type !== "transfer") showPanel("category");
    else if (s.panel) showPanel(s.panel);
  });

  el.addEventListener("click", async (e) => {
    const a = e.target.closest("[data-act]");
    if (!a) return;
    const act = a.dataset.act;
    if (act === "back") page.close();
    else if (act === "pick-account") showPanel("account");
    else if (act === "pick-to") showPanel("to");
    else if (act === "pick-category") showPanel("category");
    else if (act === "pick-amount") showPanel("amount");
    else if (act === "panel-close") showPanel(null);
    else if (act === "panel-edit") { showPanel(null); openSettingsFor(s.panel_last); }
    else if (act === "remove-photo") { e.preventDefault(); if (s.photoUrl) URL.revokeObjectURL(s.photoUrl); s.photo = null; s.photoUrl = ""; if (s.receipt) s.removePhoto = true; paint(); }
    else if (act === "view-photo") viewPhoto(s.photoUrl || receiptUrl(s.receipt));
    else if (act === "save") save(false);
    else if (act === "copy") {
      page.close();
      setTimeout(() => {
        const copy = openEntry({ type: s.type, date: today() });
        Object.assign(copy.state, { account_id: s.account_id, to_account_id: s.to_account_id, category_id: s.category_id, amount: s.amount, note: s.note, description: s.description });
        copy.repaint();
      }, 120);
    }
    else if (act === "continue") save(true);
    else if (act === "delete") {
      if (!(await confirmSheet({ title: "Delete transaction?", message: "This can't be undone." }))) return;
      try {
        await api(`/api/transactions/${s.id}`, { method: "DELETE" });
        removeLocal("transactions", s.id);
        toast("Deleted");
        page.close();
        sync().catch(() => {});
      } catch (err) { toast(err.message); }
    }
  });

  // ----- docked panel -----
  const panel = el.querySelector(".ipanel");
  // While the panel slides up or the keyboard is closing the cells move under the finger, so a tap
  // meant for one account could land on the cell below it. Ignore picks until things settle.
  let settleUntil = 0;
  const unsettled = () => { settleUntil = performance.now() + 300; };
  const ac = new AbortController();
  window.visualViewport?.addEventListener("resize", unsettled, { signal: ac.signal });
  window.visualViewport?.addEventListener("scroll", unsettled, { signal: ac.signal });
  s.unmount = () => ac.abort();
  const TITLES = { account: "Accounts", to: "Accounts", category: "Category", amount: "Amount" };
  function showPanel(kind) {
    s.panel = kind;
    if (kind) s.panel_last = kind;
    panel.hidden = !kind;
    el.classList.toggle("panel-open", !!kind);
    form.querySelectorAll(".fv").forEach((f) => f.classList.toggle("focus", f.dataset.act === `pick-${kind}`));
    if (!kind) return;
    unsettled();
    document.activeElement?.blur?.();
    panel.querySelector(".t").textContent = TITLES[kind];
    panel.querySelector(".r").innerHTML = (kind === "amount" ? "" : `<button class="icon-btn" data-act="panel-edit" aria-label="Edit">${icons.pencil}</button>`)
      + `<button class="icon-btn" data-act="panel-close" aria-label="Close">${icons.close}</button>`;
    const body = panel.querySelector(".ipanel-b");
    body.innerHTML = kind === "amount" ? keypadPanel()
      : kind === "category" ? categoryPanel(s.type, s.category_id, s.openParent)
      : accountPanel(kind === "to" ? s.to_account_id : s.account_id, kind === "to" ? s.account_id : null);
    form.querySelector(`[data-act=pick-${kind}]`)?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }
  // Money Manager walks the fields top to bottom: amount → category (or From → To) → account → note.
  const next = (kind) => {
    if (s.type === "transfer") {
      if (kind === "amount") return !s.account_id ? "account" : !s.to_account_id ? "to" : null;
      return kind === "account" && !s.to_account_id ? "to" : null;
    }
    if (kind === "amount") return !s.category_id ? "category" : !s.account_id ? "account" : null;
    return kind === "category" && !s.account_id ? "account" : null;
  };
  panel.addEventListener("click", (e) => {
    const pick = e.target.closest("[data-pick]");
    if ((pick || e.target.closest("[data-parent]")) && performance.now() < settleUntil) return;
    if (pick) {
      const id = pick.dataset.pick, kind = s.panel;
      if (kind === "account") { s.account_id = id; localStorage.setItem(LAST_ACC, id); }
      else if (kind === "to") s.to_account_id = id;
      else if (kind === "category") { s.category_id = id; s.openParent = null; }
      paint();
      const n = next(kind);
      if (n) showPanel(n); else { showPanel(null); if (kind !== "amount" && !s.note) form.querySelector("input[name=note]")?.focus(); }
      return;
    }
    const par = e.target.closest("[data-parent]");
    if (par) { s.openParent = par.dataset.parent; showPanel("category"); return; }
    const key = e.target.closest("[data-key]");
    if (key) typeKey(key.dataset.key);
  });
  function typeKey(k) {
    let v = s.amount;
    if (k === "done" || k === "=") {
      const n = evalAmount(v);
      s.amount = Number.isFinite(n) && n > 0 ? String(n) : (v && !/[-+×÷]/.test(v) ? v : "");
      paint();
      if (k === "=") { showPanel("amount"); return; }
      const n2 = next("amount");
      if (n2) showPanel(n2); else { showPanel(null); form.querySelector("input[name=note]")?.focus(); }
      return;
    }
    if (k === "back") v = v.slice(0, -1);
    else if ("+-×÷".includes(k)) v = (v === "" ? "" : /[-+×÷]$/.test(v) ? v.slice(0, -1) : v) + (v === "" && k !== "-" ? "" : k);
    else if (k === ".") { const last = v.split(/[-+×÷]/).pop(); if (!last.includes(".")) v += last ? "." : "0."; }
    else {
      const last = v.split(/[-+×÷]/).pop();
      const dec = last.includes(".") ? last.split(".")[1].length : -1;
      if (dec >= Math.max(fractionDigits(), 0) && dec !== -1) return;
      v = last === "0" ? v.slice(0, -1) + (k === "00" ? "0" : k) : v + k;
    }
    s.amount = v;
    const out = form.querySelector("[data-act=pick-amount] .amt-v");
    if (out) out.textContent = grouped(v); else paint();
  }

  const focusAmount = () => { if (!s.amount) showPanel("amount"); };

  form.addEventListener("input", (e) => {
    const t = e.target;
    if (t.name === "amount" || t.name === "note" || t.name === "description") s[t.name] = t.value;
    if (t.name === "description") autosize(t);
  });
  form.addEventListener("change", async (e) => {
    const t = e.target;
    if (t.name === "date" && t.value) { s.date = t.value; paint(); }
    else if (t.name === "time" && t.value) { s.time = t.value; paint(); }
    else if (t.name === "photo" && t.files?.[0]) {
      try {
        const blob = await downscale(t.files[0]);
        if (s.photoUrl) URL.revokeObjectURL(s.photoUrl);
        s.photo = blob; s.photoUrl = URL.createObjectURL(blob); s.removePhoto = false;
        paint();
      } catch { toast("Couldn't read that image"); }
    }
  });
  // Desktop browsers don't open pickers for transparent inputs on click; iOS does.
  form.addEventListener("click", (e) => {
    const inp = e.target.closest(".date-part input");
    if (inp?.showPicker) try { inp.showPicker(); } catch { /* not allowed */ }
  });
  form.addEventListener("submit", (e) => { e.preventDefault(); save(false); });
  form.addEventListener("focusin", (e) => { if (e.target.matches("input, textarea")) showPanel(null); });
  // New entries start the walk at the amount, like the app.
  if (!editing) setTimeout(() => showPanel("amount"), 380);
  form.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && e.target.name === "amount") { e.preventDefault(); form.querySelector("input[name=note]")?.focus(); }
  });

  async function save(again) {
    if (s.saving) return;
    const amount = /[-+×÷]/.test(s.amount) ? evalAmount(s.amount) : parseAmount(s.amount);
    if (!s.account_id) return toast("Choose an account");
    if (s.type === "transfer") {
      if (!s.to_account_id) return toast("Choose the destination account");
      if (s.to_account_id === s.account_id) return toast("Pick two different accounts");
    }
    if (!(amount > 0)) { toast("Enter an amount"); showPanel("amount"); return; }
    const body = {
      type: s.type, amount, date: `${s.date}T${s.time || "12:00"}`, account_id: s.account_id,
      note: s.note.trim(), description: s.description.trim(),
    };
    if (s.type === "transfer") body.to_account_id = s.to_account_id;
    else if (s.category_id) body.category_id = s.category_id;
    s.saving = true;
    actions.querySelectorAll("button").forEach((b) => (b.disabled = true));
    try {
      let row = editing
        ? await api(`/api/transactions/${s.id}`, { method: "PATCH", body })
        : await api("/api/transactions", { method: "POST", body: { ...body, source: "web" } });
      if (s.photo) {
        try { row = await api(`/api/transactions/${row.id}/receipt`, { method: "POST", raw: s.photo, contentType: "image/jpeg" }); }
        catch (err) { toast(`Saved, but the photo failed: ${err.message}`, 3000); }
      } else if (s.removePhoto && s.receipt) {
        await api(`/api/transactions/${row.id}/receipt`, { method: "DELETE" }).catch(() => {});
        row = { ...row, receipt: null };
      }
      upsertLocal("transactions", row);
      sync().catch(() => {});
      if (again) {
        toast("Saved — add another");
        if (s.photoUrl) URL.revokeObjectURL(s.photoUrl);
        Object.assign(s, { amount: "", note: "", description: "", photo: null, photoUrl: "", receipt: null, removePhoto: false, saving: false, time: hm(new Date()) });
        paint();
        focusAmount();
      } else {
        toast("Saved");
        page.close();
      }
    } catch (err) {
      toast(err.message, 2600);
    } finally {
      s.saving = false;
      actions.querySelectorAll("button").forEach((b) => (b.disabled = false));
    }
  }
  return paint;
}

/** "Tue, 13/10/2026" */
function mmDate(ymd) { const [y, m, d] = ymd.split("-"); return `${dowName(parseYmd(ymd).getDay())}, ${d}/${m}/${y}`; }
/** "00.41": 24-hour, as Money Manager shows it. */
function mmTime(t) { const [h, m] = t.split(":"); return `${h.padStart(2, "0")}.${m}`; }

function formHtml(s) {
  const acc = account(s.account_id);
  const to = account(s.to_account_id);
  const cat = category(s.category_id);
  const parent = cat?.parent_id ? category(cat.parent_id) : null;
  const catLabel = cat ? `${parent ? `${esc(parent.name)}/` : ""}${esc(cat.name)}` : "";
  const thumb = s.photoUrl || (s.receipt && !s.removePhoto ? receiptUrl(s.receipt) : "");
  const sym = currencySymbol(getCurrency());
  return `
    <div class="fld"><span class="flabel">Date</span>
      <div class="fv">
        <span class="date-part">${esc(mmDate(s.date))}<input type="date" name="date" value="${s.date}" aria-label="Date"></span>
        <span class="date-part">${esc(mmTime(s.time))}<input type="time" name="time" value="${s.time}" aria-label="Time"></span>
      </div></div>
    <div class="fld"><span class="flabel">Amount</span>
      <button type="button" class="fv" data-act="pick-amount"><span class="sym">${esc(sym)}</span><span class="amt-v">${esc(grouped(s.amount))}</span></button></div>
    ${s.type === "transfer" ? "" : `<div class="fld"><span class="flabel">Category</span><button type="button" class="fv" data-act="pick-category">${catLabel || ""}</button></div>`}
    <div class="fld"><span class="flabel">${s.type === "transfer" ? "From" : "Account"}</span>
      <button type="button" class="fv" data-act="pick-account">${acc ? esc(acc.name) : ""}</button></div>
    ${s.type === "transfer" ? `<div class="fld"><span class="flabel">To</span><button type="button" class="fv" data-act="pick-to">${to ? esc(to.name) : ""}</button></div>` : ""}
    <div class="fld"><label for="f-note">Note</label>
      <div class="fv"><input id="f-note" class="plain" name="note" type="text" enterkeyhint="done" placeholder="" value="${esc(s.note)}" maxlength="200"></div></div>
    <div class="form-sep"></div>
    <div class="desc-row">
      <textarea id="f-desc" class="plain" name="description" rows="1" placeholder="Description" aria-label="Description">${esc(s.description)}</textarea>
      <label class="cam" aria-label="${thumb ? "Replace" : "Add"} receipt photo">${icons.camera}<input type="file" name="photo" accept="image/*" capture="environment"></label>
    </div>
    ${thumb ? `<div class="photo-row"><div class="thumb"><img src="${esc(thumb)}" alt="Receipt" data-act="view-photo"><button type="button" class="x" data-act="remove-photo" aria-label="Remove photo">✕</button></div></div>` : ""}`;
}

function autosize(t) { if (!t) return; t.style.height = "auto"; t.style.height = `${Math.min(t.scrollHeight, 200)}px`; }

// ---------- docked input panel (Money Manager's black-header bottom panel) ----------

const pad = (n, cols) => '<span class="cell blank"></span>'.repeat((cols - (n % cols)) % cols);

function accountPanel(selected, exclude) {
  let html = "";
  for (const g of groups()) {
    const list = accounts().filter((a) => a.group_id === g.id && !a.hidden && a.id !== exclude);
    if (!list.length) continue;
    html += list.map((a) => `<button class="cell${a.id === selected ? " on" : ""}" data-pick="${a.id}">${esc(a.name)}</button>`).join("");
  }
  const n = (html.match(/class="cell/g) || []).length;
  return n ? `<div class="pgrid">${html}${pad(n, 3)}</div>` : `<div class="empty">No accounts</div>`;
}

function categoryPanel(type, selected, openParent) {
  const tree = categoryTree(type);
  if (!tree.length) return `<div class="empty">No categories yet — add some in Settings.</div>`;
  const sel = category(selected);
  const selTop = sel?.parent_id || sel?.id;
  // With sub-categories Money Manager shows two lists side by side; otherwise a 3-column grid.
  if (!tree.some((c) => c.children.length)) {
    return `<div class="pgrid">${tree.map((c) => `<button class="cell${c.id === selTop ? " on" : ""}" data-pick="${c.id}">${esc(c.name)}</button>`).join("")}${pad(tree.length, 3)}</div>`;
  }
  const parent = tree.find((c) => c.id === (openParent || selTop)) || null;
  return `<div class="plists">
    <div class="plist">${tree.map((c) => `<button class="prow${parent && c.id === parent.id ? " on" : ""}" ${c.children.length ? `data-parent="${c.id}"` : `data-pick="${c.id}"`}>
      <span>${esc(c.name)}</span>${c.children.length ? icons.chev.replace("<svg", '<svg class="chev"') : ""}</button>`).join("")}</div>
    <div class="plist sub">${parent ? [parent, ...parent.children].map((c, i) => `<button class="prow${c.id === selected ? " on" : ""}" data-pick="${c.id}"><span>${i ? esc(c.name) : `${esc(c.name)} <small>(all)</small>`}</span></button>`).join("") : ""}</div>
  </div>`;
}

// Money Manager's calculator keypad: operators on top, OK bottom right.
const KEYPAD = [["+", "-", "×", "÷"], ["7", "8", "9", "="], ["4", "5", "6", "."], ["1", "2", "3", "back"], ["", "0", "", "done"]];

function keypadPanel() {
  const noDecimals = fractionDigits() === 0;
  const label = (k) => k === "back" ? icons.backspace : k === "done" ? "OK" : k === "-" ? "−" : k;
  return `<div class="kpad">${KEYPAD.flat().map((k, i) => k === "" ? `<span class="key blank"></span>`
    : `<button class="key k-${k === "." ? "dot" : /^\d+$/.test(k) ? "n" : k === "done" ? "done" : "op"}${i < 4 ? " k-top" : ""}" data-key="${k}"${k === "." && noDecimals ? " disabled" : ""}>${label(k)}</button>`).join("")}</div>`;
}

/** "25000" → "25,000", "1200.5+300" → "1,200.5+300": commas in the integer part of each number, for display only. */
export const grouped = (expr) => String(expr).replace(/\d+/g, (d, i, all) => all[i - 1] === "." ? d : d.replace(/\B(?=(\d{3})+$)/g, ","));

/** Evaluate "12+3×2−1" style input left-to-right with × ÷ precedence. */
export function evalAmount(expr) {
  const toks = String(expr).replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").match(/\d+(?:\.\d*)?|\.\d+|[-+*/]/g);
  if (!toks) return NaN;
  const out = [];
  let sign = 1;
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i];
    if ("+-".includes(t)) { if (t === "-") sign = -1; else sign = 1; continue; }
    if ("*/".includes(t)) { const nx = Number(toks[++i]); if (!Number.isFinite(nx)) break; const v = out.pop() ?? 0; out.push(t === "*" ? v * nx : nx ? v / nx : 0); continue; }
    out.push(sign * Number(t)); sign = 1;
  }
  return Math.round(out.reduce((a, b) => a + b, 0) * 100) / 100;
}

function viewPhoto(src) {
  if (!src) return;
  openSheet({ title: "Receipt", tall: true, html: `<img class="receipt-full" src="${esc(src)}" alt="Receipt">` });
}

/** Downscale to ≤1600px on the long edge and re-encode as JPEG. */
export async function downscale(file, max = 1600, quality = 0.85) {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = url; });
    const scale = Math.min(1, max / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.round(img.naturalWidth * scale), h = Math.round(img.naturalHeight * scale);
    const canvas = document.createElement("canvas");
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, w, h);
    ctx.drawImage(img, 0, 0, w, h);
    return await new Promise((res, rej) => canvas.toBlob((b) => (b ? res(b) : rej(new Error("encode"))), "image/jpeg", quality));
  } finally { URL.revokeObjectURL(url); }
}
