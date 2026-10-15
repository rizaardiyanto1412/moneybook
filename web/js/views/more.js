// Settings tab: icon grid (configuration, accounts, budget, categories, sync, AI, backup, log out).

import { api, auth } from "../api.js";
import { readBackup, uploadBackup } from "../importer.js";
import { clearCache, accounts, budgetStatus, categoryTree, currentPeriod, db, groups, periodRange, sync, syncState, txRange, upsertLocal, removeLocal } from "../store.js";
import { currencySymbol, esc, fractionDigits, money, monthLabel, parseAmount, addMonths } from "../format.js";
import { confirmSheet, icons, monthSwitcher, openSheet, pageHeader, promptSheet, pushPage, toast } from "../ui.js";

const CURRENCIES = ["USD", "EUR", "GBP", "JPY", "KRW", "CNY", "IDR", "INR", "SGD", "MYR", "THB", "PHP", "VND", "TWD", "HKD", "AUD", "NZD", "CAD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "TRY", "AED", "SAR", "ILS", "ZAR", "BRL", "MXN", "ARS", "CLP", "COP"];
const EMOJI = ["🍜", "🍔", "☕", "🍺", "🛒", "🚖", "🚌", "⛽", "🚗", "✈️", "🏠", "💡", "📱", "💻", "🧥", "👟", "💄", "💊", "🧘", "🏋️", "🎬", "🎮", "🎵", "📚", "📙", "🎁", "🐶", "👶", "👫", "🎉", "💼", "💰", "💵", "🥇", "📈", "🏦", "💳", "🧾", "🔧", "🧹", "🪑", "🖼️", "✂️", "🏥", "📦", "❤️", "⭐", "🌱"];
const chev = icons.chev.replace("<svg", '<svg class="chev"');

const GRID = [
  ["config", "Configuration", "gear"], ["accounts", "Accounts", "accounts"], ["budgets", "Budget", "budget"], ["cats", "Category", "list"],
  ["sync", "Sync", "refresh"], ["ai", "AI Assistant", "sparkle"], ["backup", "Backup", "download"], ["password", "Password", "lock"], ["logout", "Log out", "logout"],
];

/** Settings tab: Money Manager's icon grid. */
export function createMore({ onLogout }) {
  const el = document.createElement("div");
  el.style.cssText = "display:flex;flex-direction:column;height:100%";
  el.innerHTML = `<header class="hdr"><div class="hdr-bar"><span></span><div class="hdr-title">Settings</div><span></span></div></header><div class="scroll"></div>`;

  function render() {
    const last = syncState.last ? new Date(syncState.last).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) : "never";
    el.querySelector(".scroll").innerHTML = `
      <div class="acct-card"><span class="sync-dot ${syncState.error ? "err" : syncState.last ? "ok" : ""}"></span>
        <div><b>${esc(location.host)}</b><small>${syncState.error ? esc(syncState.error) : `Synced ${esc(last)} · ${db.transactions.size} transactions`}</small></div></div>
      <div class="cgrid">${GRID.map(([k, l, ic]) => `<button data-act="${k}">${icons[ic]}<span>${l}</span></button>`).join("")}</div>
      <div class="foot">Moneybook · Money Manager clone</div>`;
  }

  el.addEventListener("click", async (e) => {
    const a = e.target.closest("[data-act]");
    if (!a) return;
    const act = a.dataset.act;
    if (act === "config") openConfiguration();
    else if (act === "budgets") openBudgets();
    else if (act === "cats") pickFromGrid("Category", [["expense", "Expenses"], ["income", "Income"]], "", (v) => openCategories(v), 2);
    else if (act === "accounts") openAccountsAdmin();
    else if (act === "sync") { try { await sync(); toast("Up to date"); } catch (err) { toast(err.message); } render(); }
    else if (act === "ai") openAiHelp();
    else if (act === "backup") openBackup();
    else if (act === "password") openPassword();
    else if (act === "logout") {
      if (await confirmSheet({ title: "Log out?", message: "You'll need to sign in again on this device.", ok: "Log out" })) onLogout();
    }
  });

  return { el, render };
}

function openConfiguration() {
  return pushPage({
    html: `${pageHeader({ title: "Configuration" })}<div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      const a = e.target.closest("[data-act]");
      if (!a) return;
      const act = a.dataset.act;
      if (act === "back") p.close();
      else if (act === "currency") pickCurrency();
      else if (act === "decimals") pickFromGrid("Decimal places", [["", "Automatic"], ["0", "None · 1,000"], ["2", "Two · 1,000.00"]], db.settings.decimals || "", (v) => saveSettings({ decimals: v }), 1);
      else if (act === "startday") pickFromGrid("Month start day", Array.from({ length: 28 }, (_, i) => [String(i + 1), String(i + 1)]), db.settings.month_start_day || "1", (v) => saveSettings({ month_start_day: v }), 4);
      else if (act === "weekstart") pickFromGrid("Week starts on", [["0", "Sunday"], ["1", "Monday"]], db.settings.week_start || "0", (v) => saveSettings({ week_start: v }), 2);
      else if (act === "defacc") pickFromGrid("Default account", accounts().filter((x) => !x.hidden).map((x) => [x.id, x.name]), db.settings.default_account_id, (v) => saveSettings({ default_account_id: v }));
      else if (act === "tz") { const tz = Intl.DateTimeFormat().resolvedOptions().timeZone; if (tz !== db.settings.timezone) saveSettings({ timezone: tz }); }
    }),
    render: (p) => {
      const s = db.settings;
      const defAcc = db.accounts.get(s.default_account_id)?.name || "—";
      const deviceTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      p.el.querySelector(".scroll").innerHTML = `<div class="cfg">
        <button class="row" data-act="currency"><span class="lbl">Main Currency Setting</span><span class="val">${esc(s.currency)} (${esc(currencySymbol(s.currency))})</span>${chev}</button>
        <button class="row" data-act="decimals"><span class="lbl">Decimal Places</span><span class="val">${s.decimals ? (s.decimals === "0" ? "None" : s.decimals) : `Automatic (${fractionDigits()})`}</span>${chev}</button>
        <button class="row" data-act="startday"><span class="lbl">Monthly Start Date</span><span class="val">Every month ${esc(s.month_start_day || "1")}</span>${chev}</button>
        <button class="row" data-act="weekstart"><span class="lbl">Weekly Start Day</span><span class="val">${s.week_start === "1" ? "Monday" : "Sunday"}</span>${chev}</button>
        <button class="row" data-act="defacc"><span class="lbl">Default Account</span><span class="val">${esc(defAcc)}</span>${chev}</button>
        <button class="row" data-act="tz"><span class="lbl">Time Zone<span class="sub">${s.timezone !== deviceTz ? `This iPhone: ${esc(deviceTz)} — tap to use` : "Matches this iPhone"}</span></span><span class="val">${esc(s.timezone)}</span></button>
      </div>`;
    },
  });
}

/** Set or change the email + password used to sign in to the web app. */
async function openPassword() {
  let st;
  try { st = await api("/api/auth/status"); } catch (e) { toast(e.message); return; }
  // Signed in with the API token (the master key): the current password isn't needed.
  const needCurrent = st.hasPassword && auth.get().startsWith("s_");
  openSheet({
    title: st.hasPassword ? "Change password" : "Set up sign-in",
    html: `<form class="sheet-pad" autocomplete="on">
      <p class="muted" style="margin:2px 2px 4px;line-height:1.45">${st.hasPassword
        ? "Changing it signs out your other devices."
        : "Sign in with an email and password on your devices instead of the API token. Your AI keeps using the token."}</p>
      <label class="field-lbl">Email</label>
      <input class="input" name="email" type="email" autocomplete="username" value="${esc(st.email || "")}" required>
      ${needCurrent ? `<label class="field-lbl">Current password</label><input class="input" name="current" type="password" autocomplete="current-password" required>` : ""}
      <label class="field-lbl">${st.hasPassword ? "New password" : "Password"}</label>
      <input class="input" name="password" type="password" autocomplete="new-password" minlength="8" placeholder="At least 8 characters" required>
      <label class="field-lbl">Confirm password</label>
      <input class="input" name="confirm" type="password" autocomplete="new-password" required>
      <div class="err" style="color:var(--exp);font-size:14px;min-height:20px;margin-top:10px"></div>
      <button class="btn block primary" style="margin-top:4px">Save</button>
      ${st.hasPassword ? `<button type="button" class="btn block ghost" data-all style="margin-top:10px">Sign out all devices</button>` : ""}
    </form>`,
    onMount: (el, sheet) => {
      const form = el.querySelector("form");
      const err = el.querySelector(".err");
      form.addEventListener("submit", async (e) => {
        e.preventDefault();
        if (form.password.value !== form.confirm.value) { err.textContent = "Passwords don't match."; return; }
        const btn = form.querySelector(".btn.primary");
        btn.disabled = true; err.textContent = "";
        try {
          await api("/api/auth/password", { method: "PUT", body: { email: form.email.value, password: form.password.value, current: form.current?.value } });
          sheet.close();
          toast(st.hasPassword ? "Password changed" : "Sign-in set up. Use it on your other devices.", 2600);
        } catch (e2) { err.textContent = e2.message; btn.disabled = false; }
      });
      el.querySelector("[data-all]")?.addEventListener("click", async () => {
        if (!(await confirmSheet({ title: "Sign out all devices?", message: "Every device signed in with your password will need to sign in again, including this one if it used the password.", ok: "Sign out all" }))) return;
        try { await api("/api/auth/logout-all", { method: "POST" }); sheet.close(); toast("Signed out everywhere"); } catch (e2) { toast(e2.message); }
      });
    },
  });
}

function openAiHelp() {
  const url = `${location.origin}/mcp`;
  openSheet({
    title: "AI Assistant", tall: true,
    html: `<div class="sheet-pad ai-help">
      <p>Your AI can add, edit and summarise expenses here through MCP. Point it at:</p>
      <code>${esc(url)}</code>
      <p>with the header <code>Authorization: Bearer &lt;your token&gt;</code>. Claude Code:</p>
      <code>claude mcp add --transport http moneybook ${esc(url)} --header "Authorization: Bearer &lt;token&gt;"</code>
      <p class="muted">Rows the AI adds show a small ✦ next to the note.</p></div>`,
  });
}

/** Backup: export everything as JSON, or import a Money Manager .mmbak. */
function openBackup() {
  openSheet({
    title: "Backup",
    html: `<div class="sheet-pad backup">
      <button class="row tap" data-b="export">${icons.download}<span class="lbl">Export<span class="sub">Download all your data as a JSON file</span></span></button>
      <label class="row tap">${icons.upload}<span class="lbl">Import from Money Manager<span class="sub">Choose a .mmbak backup exported from Money Manager</span></span>
        <input type="file" hidden></label>
      <div class="imp"></div>
    </div>`,
    onMount: (el, sheet) => {
      el.querySelector("[data-b=export]").addEventListener("click", () => { downloadBackup(); sheet.close(); });
      el.querySelector("input[type=file]").addEventListener("change", (e) => {
        const file = e.target.files[0];
        e.target.value = "";
        if (file) previewImport(el.querySelector(".imp"), file, sheet);
      });
    },
  });
}

const IMPORT_LABELS = { transactions: "Transactions", accounts: "Accounts", categories: "Categories", account_groups: "Account groups", budgets: "Budgets" };

async function previewImport(box, file, sheet) {
  box.innerHTML = `<p class="muted imp-status">Reading ${esc(file.name)}…</p>`;
  let result;
  try {
    result = await readBackup(file, db.settings.timezone && db.settings.timezone !== "UTC" ? db.settings.timezone : Intl.DateTimeFormat().resolvedOptions().timeZone);
  } catch (e) {
    box.innerHTML = `<p class="imp-err">${esc(e.message)}</p>`;
    return;
  }
  const { counts, warnings, flavor, data } = result;
  box.innerHTML = `
    <div class="imp-card">
      <b>${esc(file.name)}</b><small>Money Manager ${flavor === "iphone" ? "iPhone" : "Android"} backup${data.settings.currency ? ` · ${esc(data.settings.currency)}` : ""}</small>
      <dl>${Object.entries(IMPORT_LABELS).map(([k, l]) => `<dt>${l}</dt><dd>${(counts[k] ?? 0).toLocaleString()}</dd>`).join("")}</dl>
      ${warnings.map((w) => `<p class="imp-warn">${esc(w)}</p>`).join("")}
    </div>
    <div class="seg imp-mode" style="margin:12px 0 4px">
      <button type="button" class="on" data-mode="replace">Replace everything</button><button type="button" data-mode="merge">Add to existing</button>
    </div>
    <p class="muted imp-hint"></p>
    <button class="btn block primary" data-go>Import</button>`;
  let mode = "replace";
  const hint = () => {
    box.querySelector(".imp-hint").textContent = mode === "replace"
      ? `Your current ${db.transactions.size} transactions, accounts and categories are removed and replaced by the backup. Export first if you want a copy.`
      : "Backup rows are added next to your current data. Importing the same backup again updates those rows instead of duplicating them.";
  };
  hint();
  box.querySelector(".imp-mode").addEventListener("click", (e) => {
    const b = e.target.closest("[data-mode]");
    if (!b) return;
    mode = b.dataset.mode;
    box.querySelectorAll(".imp-mode button").forEach((x) => x.classList.toggle("on", x === b));
    hint();
  });
  box.querySelector("[data-go]").addEventListener("click", async (e) => {
    const btn = e.currentTarget;
    if (mode === "replace" && !(await confirmSheet({ title: "Replace all data?", message: "Everything currently in Moneybook will be replaced by this backup.", ok: "Replace and import" }))) return;
    btn.disabled = true; btn.textContent = "Importing…";
    try {
      await uploadBackup(data, { replace: mode === "replace", onProgress: (n, total) => { btn.textContent = `Importing… ${n}/${total}`; } });
      clearCache();
      await sync();
      sheet.close();
      toast(`Imported ${counts.transactions.toLocaleString()} transactions`, 2600);
    } catch (err) {
      btn.disabled = false; btn.textContent = "Try again";
      box.querySelector(".imp-hint").innerHTML = `<span class="imp-err">${esc(err.message)}</span>`;
    }
  });
}

async function downloadBackup() {
  try {
    const data = await api("/api/sync?since=0");
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `moneybook-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  } catch (e) { toast(e.message); }
}

async function saveSettings(patch) {
  try {
    await api("/api/settings", { method: "PATCH", body: patch });
    await sync().catch(() => {});
    toast("Saved");
  } catch (e) { toast(e.message); }
}

function pickFromGrid(title, options, selected, onPick, cols = 3) {
  openSheet({
    title,
    html: `<div class="grid3" style="grid-template-columns:repeat(${cols},1fr);border-top:0">${options.map(([v, l]) => `<button data-v="${esc(v)}" class="${v === selected ? "on" : ""}">${esc(l)}</button>`).join("")}${"<button disabled></button>".repeat((cols - (options.length % cols)) % cols)}</div>`,
    onMount: (el, sh) => el.querySelector(".sheet-b").addEventListener("click", (e) => {
      const b = e.target.closest("button[data-v]");
      if (b) { sh.close(); onPick(b.dataset.v); }
    }),
  });
}

function pickCurrency() {
  const cur = db.settings.currency;
  openSheet({
    title: "Currency", tall: true,
    html: `<form class="sheet-pad" style="padding-bottom:4px"><input class="input" name="code" placeholder="Other ISO code, e.g. NGN" maxlength="3" autocapitalize="characters" autocomplete="off"></form>
      ${CURRENCIES.map((c) => `<button class="row" data-v="${c}"><span class="lbl">${c}</span><span class="val">${esc(currencySymbol(c))}</span>${c === cur ? `<span style="color:var(--accent)">✓</span>` : ""}</button>`).join("")}`,
    onMount: (el, sh) => {
      el.addEventListener("click", (e) => { const b = e.target.closest("[data-v]"); if (b) { sh.close(); saveSettings({ currency: b.dataset.v }); } });
      el.querySelector("form").addEventListener("submit", (e) => {
        e.preventDefault();
        const code = e.target.code.value.trim().toUpperCase();
        try { new Intl.NumberFormat("en", { style: "currency", currency: code }); } catch { return toast("Unknown currency code"); }
        sh.close(); saveSettings({ currency: code });
      });
    },
  });
}

// ---------- budgets ----------

export function openBudgets() {
  let ym = currentPeriod();
  return pushPage({
    html: `${pageHeader({ title: "Budget" })}<div class="hdr" style="padding-top:0"><div class="sw" style="display:flex;justify-content:center"></div></div><div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", async (e) => {
      const a = e.target.closest("[data-act]");
      if (a?.dataset.act === "back") return p.close();
      if (a?.dataset.act === "prev" || a?.dataset.act === "next") { ym = addMonths(ym, a.dataset.act === "prev" ? -1 : 1); return p.render(); }
      const b = e.target.closest("[data-bud]");
      if (b) editBudget(b.dataset.bud || null, b.dataset.name, ym);
    }),
    render: (p) => {
      p.el.querySelector(".sw").innerHTML = monthSwitcher(monthLabel(ym));
      const { from, to } = periodRange(ym);
      const list = txRange(from, to);
      const status = budgetStatus(ym, list);
      const byId = new Map(status.map((s) => [s.isTotal ? "" : s.category_id, s]));
      const row = (id, icon, name) => {
        const s = byId.get(id);
        const pct = s ? Math.min(s.percent, 100) : 0;
        const cls = s && s.percent > 100 ? "over" : s && s.percent > 85 ? "warn" : "";
        return `<button class="bud" style="display:block;width:100%;text-align:left" data-bud="${id}" data-name="${esc(name)}">
          <div class="bud-top"><span>${icon ? esc(icon) + " " : ""}${esc(name)}${s?.month ? ` <small class="muted">(${esc(monthLabel(s.month))} only)</small>` : ""}</span>
            <span class="r">${s ? `${money(s.spent)} / <b style="color:var(--fg)">${money(s.budget)}</b>` : `<span style="color:var(--accent)">Set</span>`}</span></div>
          ${s ? `<div class="bar"><i class="${cls}" style="width:${pct}%"></i></div><div class="bud-bot"><span>${Math.round(s.percent)}%</span><span class="${s.remaining < 0 ? "exp" : ""}">${s.remaining < 0 ? "Over by " + money(-s.remaining) : money(s.remaining) + " left"}</span></div>` : ""}
        </button>`;
      };
      p.el.querySelector(".scroll").innerHTML = `<div class="grouped">
        <div class="card">${row("", "🎯", "Total")}</div>
        <div class="sec-title">Monthly budget by category</div>
        <div class="card">${categoryTree("expense").map((c) => row(c.id, c.icon, c.name)).join("")}</div>
        <p class="foot" style="padding:0 24px;line-height:1.5">Budgets repeat every month unless you choose “only this month”. Set 0 to remove.</p>
      </div>`;
    },
  });
}

function editBudget(categoryId, name, ym) {
  const existing = [...db.budgets.values()].filter((b) => (b.category_id ?? "") === (categoryId ?? ""));
  const monthly = existing.find((b) => b.month === ym);
  const every = existing.find((b) => !b.month);
  openSheet({
    title: `${name} budget`,
    html: `<form class="sheet-pad">
      <label class="field-lbl">Amount (${esc(db.settings.currency)})</label>
      <input class="input" name="amount" inputmode="decimal" placeholder="0" value="${monthly?.amount ?? every?.amount ?? ""}" autocomplete="off">
      <div class="seg" style="margin:14px 0 0"><button type="button" data-scope="every" class="${monthly ? "" : "on"}">Every month</button><button type="button" data-scope="month" class="${monthly ? "on" : ""}">Only ${esc(monthLabel(ym))}</button></div>
      <button class="btn block primary" style="margin-top:16px">Save</button>
      ${monthly || every ? `<button type="button" class="btn block ghost" data-act="remove" style="color:var(--exp)">Remove budget</button>` : ""}
    </form>`,
    onMount: (el, sh) => {
      let scope = monthly ? "month" : "every";
      el.querySelector(".seg").addEventListener("click", (e) => {
        const b = e.target.closest("[data-scope]"); if (!b) return;
        scope = b.dataset.scope;
        el.querySelectorAll("[data-scope]").forEach((x) => x.classList.toggle("on", x === b));
      });
      const put = async (amount, month) => {
        await api("/api/budgets", { method: "PUT", body: { category_id: categoryId, category: categoryId ? undefined : "Total", amount, month } });
      };
      el.querySelector("form").addEventListener("submit", async (e) => {
        e.preventDefault();
        const v = parseAmount(e.target.amount.value || "0");
        if (!(v >= 0)) return toast("Enter an amount");
        try { await put(v, scope === "month" ? ym : null); sh.close(); await sync(); toast("Budget saved"); } catch (err) { toast(err.message); }
      });
      el.querySelector("[data-act=remove]")?.addEventListener("click", async () => {
        try {
          if (monthly) await put(0, ym); else if (every) await put(0, null);
          sh.close(); await sync(); toast("Removed");
        } catch (err) { toast(err.message); }
      });
      setTimeout(() => el.querySelector("input").focus(), 350);
    },
  });
}

// ---------- categories ----------

export function openCategories(type) {
  return pushPage({
    html: `${pageHeader({ title: type === "income" ? "Income categories" : "Expense categories", right: `<button class="icon-btn" data-act="add" aria-label="Add category">${icons.plus}</button>` })}<div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      const a = e.target.closest("[data-act]");
      if (a?.dataset.act === "back") return p.close();
      if (a?.dataset.act === "add") return editCategory({ type });
      if (a?.dataset.act === "addsub") return editCategory({ type, parent_id: a.dataset.parent });
      const c = e.target.closest("[data-cat]");
      if (c) editCategory(db.categories.get(c.dataset.cat));
    }),
    render: (p) => {
      const tree = categoryTree(type);
      p.el.querySelector(".scroll").innerHTML = `<div class="grouped"><div class="card">${tree.map((c) => `
        <button class="row" data-cat="${c.id}"><span class="em">${esc(c.icon || "•")}</span><span class="lbl">${esc(c.name)}</span>${c.children.length ? `<span class="val">${c.children.length}</span>` : ""}${chev}</button>
        ${c.children.map((s) => `<button class="row indent" data-cat="${s.id}" style="min-height:44px"><span class="lbl muted">${s.icon ? esc(s.icon) + " " : ""}${esc(s.name)}</span>${chev}</button>`).join("")}`).join("")}
      </div><p class="foot">Tap a category to rename it, change its emoji, add subcategories or delete it.</p></div>`;
    },
  });
}

function editCategory(cat) {
  const isNew = !cat.id;
  const parent = cat.parent_id ? db.categories.get(cat.parent_id) : null;
  let icon = cat.icon || (isNew && !parent ? "📦" : "");
  openSheet({
    title: isNew ? (parent ? `New in ${parent.name}` : "New category") : "Edit category", tall: true,
    html: `<form class="sheet-pad">
      <label class="field-lbl">Name</label>
      <input class="input" name="name" value="${esc(cat.name || "")}" placeholder="${parent ? "e.g. Lunch" : "e.g. Groceries"}" autocomplete="off" maxlength="40">
      <label class="field-lbl">Emoji</label>
      <input class="input" name="icon" value="${esc(icon)}" placeholder="Type or pick an emoji" autocomplete="off" style="font-size:22px">
      <div class="emoji-grid">${EMOJI.map((e) => `<button type="button" data-emoji="${e}" class="${e === icon ? "on" : ""}">${e}</button>`).join("")}</div>
      <button class="btn block primary" style="margin-top:16px">${isNew ? "Add" : "Save"}</button>
      ${!isNew && !cat.parent_id ? `<button type="button" class="btn block ghost" data-act="addsub">＋ Add subcategory</button>` : ""}
      ${isNew ? "" : `<button type="button" class="btn block ghost" data-act="del" style="color:var(--exp)">Delete category</button>`}
    </form>`,
    onMount: (el, sh) => {
      const form = el.querySelector("form");
      el.querySelector(".emoji-grid").addEventListener("click", (e) => {
        const b = e.target.closest("[data-emoji]"); if (!b) return;
        form.icon.value = b.dataset.emoji;
        el.querySelectorAll("[data-emoji]").forEach((x) => x.classList.toggle("on", x === b));
      });
      form.addEventListener("submit", async (e) => {
        e.preventDefault();
        const name = form.name.value.trim();
        if (!name) return toast("Enter a name");
        const iconV = [...new Intl.Segmenter().segment(form.icon.value.trim())][0]?.segment ?? "";
        try {
          const row = isNew
            ? await api("/api/categories", { method: "POST", body: { type: cat.type, name, icon: iconV, parent_id: cat.parent_id || undefined } })
            : await api(`/api/categories/${cat.id}`, { method: "PATCH", body: { name, icon: iconV } });
          upsertLocal("categories", row);
          sh.close(); toast(isNew ? "Added" : "Saved");
          sync().catch(() => {});
        } catch (err) { toast(err.message); }
      });
      el.querySelector("[data-act=addsub]")?.addEventListener("click", () => { sh.close(); setTimeout(() => editCategory({ type: cat.type, parent_id: cat.id }), 250); });
      el.querySelector("[data-act=del]")?.addEventListener("click", async () => {
        const kids = [...db.categories.values()].filter((c) => c.parent_id === cat.id);
        const ok = await confirmSheet({ title: `Delete “${cat.name}”?`, message: `${kids.length ? `Its ${kids.length} subcategories will be deleted too. ` : ""}Existing transactions keep their amounts but show as uncategorized.` });
        if (!ok) return;
        try {
          for (const k of kids) { await api(`/api/categories/${k.id}`, { method: "DELETE" }); removeLocal("categories", k.id); }
          await api(`/api/categories/${cat.id}`, { method: "DELETE" });
          removeLocal("categories", cat.id);
          sh.close(); toast("Deleted");
          sync().catch(() => {});
        } catch (err) { toast(err.message); }
      });
    },
  });
}

// ---------- accounts ----------

export function openAccountsAdmin() {
  return pushPage({
    html: `${pageHeader({ title: "Accounts", right: `<button class="icon-btn" data-act="add" aria-label="Add account">${icons.plus}</button>` })}<div class="scroll"></div>`,
    onMount: (el, p) => el.addEventListener("click", (e) => {
      const a = e.target.closest("[data-act]");
      if (a?.dataset.act === "back") return p.close();
      if (a?.dataset.act === "add") return openAccountEditor();
      const r = e.target.closest("[data-acc]");
      if (r) openAccountEditor(db.accounts.get(r.dataset.acc));
    }),
    render: (p) => {
      let html = `<div class="grouped">`;
      for (const g of groups()) {
        const list = accounts().filter((a) => a.group_id === g.id);
        if (!list.length) continue;
        html += `<div class="sec-title">${esc(g.name)}</div><div class="card">${list.map((a) => `<button class="row" data-acc="${a.id}"><span class="lbl">${esc(a.name)}${a.hidden ? ` <small class="muted">hidden</small>` : ""}</span><span class="val">${money(a.initial_balance)} start</span>${chev}</button>`).join("")}</div>`;
      }
      p.el.querySelector(".scroll").innerHTML = html + `</div>`;
    },
  });
}

export function openAccountEditor(acc) {
  const isNew = !acc;
  acc = acc || { name: "", group_id: groups().find((g) => g.name === "Accounts")?.id || groups()[0]?.id, initial_balance: 0, include_in_totals: 1, hidden: 0 };
  openSheet({
    title: isNew ? "New account" : "Edit account", tall: true,
    html: `<form class="sheet-pad">
      <label class="field-lbl">Group</label>
      <select class="input" name="group_id">${groups().map((g) => `<option value="${g.id}" ${g.id === acc.group_id ? "selected" : ""}>${esc(g.name)}</option>`).join("")}</select>
      <label class="field-lbl">Name</label>
      <input class="input" name="name" value="${esc(acc.name)}" placeholder="e.g. Chase Checking" autocomplete="off">
      <label class="field-lbl">Starting balance</label>
      <input class="input" name="initial_balance" inputmode="decimal" value="${acc.initial_balance || ""}" placeholder="0" autocomplete="off">
      <label class="row" style="padding:0 2px;border:0"><span class="lbl">Include in totals</span><input type="checkbox" name="include_in_totals" ${acc.include_in_totals ? "checked" : ""}></label>
      <label class="row" style="padding:0 2px;border:0"><span class="lbl">Hide from lists</span><input type="checkbox" name="hidden" ${acc.hidden ? "checked" : ""}></label>
      <button class="btn block primary" style="margin-top:8px">${isNew ? "Add account" : "Save"}</button>
      ${isNew ? "" : `<button type="button" class="btn block ghost" data-act="del" style="color:var(--exp)">Delete account</button>`}
    </form>`,
    onMount: (el, sh) => {
      const f = el.querySelector("form");
      f.addEventListener("submit", async (e) => {
        e.preventDefault();
        const name = f.name.value.trim();
        if (!name) return toast("Enter a name");
        const ib = f.initial_balance.value.trim() ? parseAmount(f.initial_balance.value) : 0;
        if (!Number.isFinite(ib)) return toast("Invalid balance");
        const body = { name, group_id: f.group_id.value, initial_balance: ib, include_in_totals: f.include_in_totals.checked, hidden: f.hidden.checked };
        try {
          const row = isNew ? await api("/api/accounts", { method: "POST", body }) : await api(`/api/accounts/${acc.id}`, { method: "PATCH", body });
          upsertLocal("accounts", row);
          sh.close(); toast("Saved"); sync().catch(() => {});
        } catch (err) { toast(err.message); }
      });
      el.querySelector("[data-act=del]")?.addEventListener("click", async () => {
        const n = [...db.transactions.values()].filter((t) => t.account_id === acc.id || t.to_account_id === acc.id).length;
        if (!(await confirmSheet({ title: `Delete “${acc.name}”?`, message: n ? `${n} transactions still reference it; they will remain but won't count toward any listed account.` : "" }))) return;
        try { await api(`/api/accounts/${acc.id}`, { method: "DELETE" }); removeLocal("accounts", acc.id); sh.close(); toast("Deleted"); sync().catch(() => {}); }
        catch (err) { toast(err.message); }
      });
    },
  });
}
