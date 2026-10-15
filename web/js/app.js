// Moneybook iPhone web app: boot, login, tab shell and background sync.

import { api, auth } from "./api.js";
import { clearCache, db, loadCache, subscribe, sync } from "./store.js";
import { esc } from "./format.js";
import { flashIds } from "./components.js";
import { h, icons, popAll, popPage, renderStack, stack, toast } from "./ui.js";
import { play } from "./motion.js";
import { createTrans } from "./views/trans.js";
import { createStats } from "./views/stats.js";
import { createAccounts } from "./views/accounts.js";
import { createMore } from "./views/more.js";
import { openEntry } from "./views/entry.js";

const SYNC_MS = 15000;
const appEl = document.getElementById("app");
let shell = null;

// ---------- login ----------

/**
 * Sign-in screen. With a password set: email + password (a device session is stored).
 * Otherwise, or via "Use API token", the API token itself. A ?token= link pre-fills and submits it.
 */
async function showLogin(message = "", prefill = "") {
  shell = null;
  popAll();
  appEl.innerHTML = "";
  let hasPassword = false;
  if (!prefill) { try { hasPassword = (await api("/api/auth/status", { token: "" })).hasPassword; } catch { /* offline: offer the token */ } }
  let mode = hasPassword ? "password" : "token";

  const el = h(`<form class="login" autocomplete="on">
    <img class="logo" src="/icons/icon-192.png" alt="">
    <h1>Moneybook</h1>
    <p class="hint"></p>
    <div class="fields"></div>
    <button class="btn block primary">Sign in</button>
    <div class="err">${esc(message)}</div>
    <button type="button" class="switch" hidden></button>
  </form>`);
  appEl.appendChild(el);
  const err = el.querySelector(".err");
  const btn = el.querySelector(".btn");

  const paint = () => {
    el.querySelector(".hint").innerHTML = mode === "password"
      ? "Sign in to your Moneybook."
      : `Enter the API token for your Moneybook server.${hasPassword ? "" : "<br>You can set up an email and password in Settings afterwards."}`;
    el.querySelector(".fields").innerHTML = mode === "password"
      ? `<input class="input" name="email" type="email" placeholder="Email" autocomplete="username" autocapitalize="off" required>
         <input class="input" name="password" type="password" placeholder="Password" autocomplete="current-password" enterkeyhint="go" required style="margin-top:10px">`
      : `<input class="input" name="token" type="password" placeholder="API token" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="go" required>`;
    const sw = el.querySelector(".switch");
    sw.hidden = !hasPassword;
    sw.textContent = mode === "password" ? "Use API token instead" : "Sign in with email";
  };
  paint();
  el.querySelector(".switch").addEventListener("click", () => { mode = mode === "password" ? "token" : "password"; err.textContent = ""; paint(); });

  el.addEventListener("submit", async (e) => {
    e.preventDefault();
    btn.disabled = true; btn.textContent = "Checking…"; err.textContent = "";
    try {
      let token;
      if (mode === "password") {
        token = (await api("/api/auth/login", { method: "POST", token: "", body: { email: el.email.value, password: el.password.value } })).session;
      } else {
        token = el.token.value.trim();
        await api("/api/settings", { token });
      }
      auth.set(token);
      clearCache();
      await sync();
      await adoptDeviceTimezone();
      showApp();
    } catch (e2) {
      err.textContent = e2.status === 401 ? (mode === "password" ? e2.message : "That token isn't valid.") : e2.message;
      btn.disabled = false; btn.textContent = "Sign in";
    }
  });
  if (prefill) { el.token.value = prefill; el.requestSubmit(); }
}

/** The API expects clients to set the user's timezone; do it once if it's still the default. */
async function adoptDeviceTimezone() {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (tz && db.settings.timezone === "UTC" && tz !== "UTC") {
    try { await api("/api/settings", { method: "PATCH", body: { timezone: tz } }); await sync(); } catch { /* not critical */ }
  }
}

function logout(message = "") {
  // A password session is revoked on the server too; the API token is left alone.
  if (auth.get().startsWith("s_")) api("/api/auth/logout", { method: "POST" }).catch(() => {});
  auth.clear();
  clearCache();
  showLogin(message);
}

// ---------- tab shell ----------

/** Money Manager labels the first tab with today's date, e.g. "10/13". */
const todayLabel = () => { const d = new Date(); return `${String(d.getMonth() + 1).padStart(2, "0")}/${String(d.getDate()).padStart(2, "0")}`; };
const TABS = [
  ["trans", todayLabel, () => icons.book],
  ["stats", () => "Stats", () => icons.stats],
  ["accounts", () => "Accounts", () => icons.accounts],
  ["more", () => "Settings", () => icons.gear],
];

/** Sidebar labels on desktop, where the date label would be cryptic. */
const DESK = { trans: "Transactions" };

function showApp() {
  appEl.innerHTML = "";
  const root = h(`<section class="page root">
    <div class="panes" style="flex:1;min-height:0;position:relative"></div>
    <button class="fab" aria-label="Add transaction">${icons.plus}<span>Add</span></button>
    <nav class="tabbar"><div class="brand"><img src="/icons/icon-192.png" alt="">Moneybook</div>${TABS.map(([k, l, ic]) => `<button data-tab="${k}">${ic()}<span>${l()}</span><i>${DESK[k] || l()}</i></button>`).join("")}</nav>
  </section>`);
  appEl.appendChild(root);
  const views = {
    trans: createTrans(),
    stats: createStats(),
    accounts: createAccounts(),
    more: createMore({ onLogout: () => logout() }),
  };
  const panes = root.querySelector(".panes");
  for (const [k, v] of Object.entries(views)) {
    v.el.dataset.pane = k;
    v.el.style.position = "absolute";
    v.el.style.inset = "0";
    panes.appendChild(v.el);
  }
  shell = { root, views, tab: sessionStorage.getItem("mb.tab") || "trans", dirty: new Set() };

  const select = (tab) => {
    shell.tab = tab;
    sessionStorage.setItem("mb.tab", tab);
    for (const [k, v] of Object.entries(views)) v.el.classList.toggle("hidden", k !== tab);
    root.querySelectorAll(".tabbar button").forEach((b) => b.classList.toggle("on", b.dataset.tab === tab));
    root.querySelector(".fab").classList.toggle("hidden", !views[tab].fab);
    if (shell.dirty.has(tab) || !views[tab].rendered) { views[tab].render(); views[tab].rendered = true; shell.dirty.delete(tab); }
  };
  root.querySelector(".tabbar").addEventListener("click", (e) => {
    const b = e.target.closest("[data-tab]");
    if (!b) return;
    // Pages that keep the tab bar (an account's ledger) close when you switch tabs, like the app.
    if (stack.length) { popAll(); if (b.dataset.tab === shell.tab) return; }
    if (b.dataset.tab === shell.tab) views[shell.tab].el.querySelector(".scroll")?.scrollTo({ top: 0, behavior: "smooth" });
    else {
      select(b.dataset.tab);
      const v = views[b.dataset.tab];
      play(v.el, "fade");
      play(v.el.querySelector(".pie-wrap svg"), "sweep");
      play(b.querySelector("svg"), "pop");
    }
  });
  // Desktop: pages open as a side panel over a dimmed root; clicking the dim area closes the top one.
  root.addEventListener("click", (e) => { if (e.target === root && stack.length) popPage(); });
  root.querySelector(".fab").addEventListener("click", () => {
    openEntry({ date: shell.tab === "trans" ? views.trans.newEntryDate() : undefined });
  });
  select(shell.tab);
}

/** Re-render the visible tab now; others lazily when selected. */
function refreshViews() {
  if (!shell) return;
  for (const k of Object.keys(shell.views)) shell.dirty.add(k);
  const v = shell.views[shell.tab];
  v.render(); v.rendered = true; shell.dirty.delete(shell.tab);
  renderStack();
}

subscribe((info) => {
  if (info?.newIds?.length) {
    flashIds(info.newIds);
    const ai = info.newIds.filter((id) => db.transactions.get(id)?.source === "ai").length;
    if (ai) toast(`✨ ${ai} new transaction${ai > 1 ? "s" : ""} from your AI`, 2600);
  }
  refreshViews();
});

// ---------- background sync ----------

let timer = null;
function startSyncLoop() {
  clearInterval(timer);
  timer = setInterval(() => { if (document.visibilityState === "visible" && auth.get() && shell) quietSync(); }, SYNC_MS);
}
function quietSync() {
  sync().catch((e) => { if (e.status !== 401) refreshMoreSoon(); });
}
function refreshMoreSoon() { if (shell?.tab === "more") shell.views.more.render(); }

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && auth.get() && shell) { quietSync(); startSyncLoop(); }
});
window.addEventListener("online", () => auth.get() && shell && quietSync());
window.addEventListener("mb:unauthorized", () => logout("Your token was rejected. Please sign in again."));

// Escape closes the top sheet, then the top page (desktop keyboards).
document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape" || !shell) return;
  const bgs = document.querySelectorAll(".sheet-bg.in");
  if (bgs.length) bgs[bgs.length - 1].click();
  else if (stack.length) popPage();
});

// The first tab's date label should follow the calendar.
setInterval(() => {
  const b = shell?.root.querySelector('[data-tab="trans"] span');
  if (b && b.textContent !== todayLabel()) b.textContent = todayLabel();
}, 60000);

// ---------- boot ----------

// A link like /?token=… signs in directly; the token is removed from the address bar right away.
const linkToken = new URLSearchParams(location.search).get("token");
if (linkToken) history.replaceState(null, "", location.pathname);

if (linkToken && linkToken !== auth.get()) {
  showLogin("", linkToken);
} else if (auth.get()) {
  loadCache();
  showApp();
  quietSync();
} else {
  showLogin();
}
startSyncLoop();

if ("serviceWorker" in navigator && location.protocol !== "file:") {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}
