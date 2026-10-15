// Small UI toolkit: icons, page stack (push / modal), bottom sheets, toast.

import { esc } from "./format.js";

const svg = (body, vb = "0 0 24 24") =>
  `<svg viewBox="${vb}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;

export const icons = {
  left: svg('<path d="M15 5l-7 7 7 7"/>'),
  right: svg('<path d="M9 5l7 7-7 7"/>'),
  chev: svg('<path d="M9 5l7 7-7 7"/>'),
  plus: svg('<path d="M12 5v14M5 12h14"/>'),
  close: svg('<path d="M6 6l12 12M18 6L6 18"/>'),
  search: svg('<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>'),
  filter: svg('<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/><path d="M4 12h12M20 12h0"/><circle cx="18" cy="12" r="0"/>'),
  camera: svg('<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2.2l1.4-2h5.8l1.4 2h2.2A1.5 1.5 0 0 1 20 8.5v9A1.5 1.5 0 0 1 18.5 19h-13A1.5 1.5 0 0 1 4 17.5z"/><circle cx="12" cy="13" r="3.3"/>'),
  backspace: svg('<path d="M9 5h10.5A1.5 1.5 0 0 1 21 6.5v11a1.5 1.5 0 0 1-1.5 1.5H9l-6-7z"/><path d="M12 9.5l5 5M17 9.5l-5 5"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  calc: svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M8 7h8M8.5 11.5h.01M12 11.5h.01M15.5 11.5h.01M8.5 15h.01M12 15h.01M15.5 15h.01M8.5 18h.01M12 18h.01M15.5 18h.01"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  budget: svg('<circle cx="12" cy="12" r="8.5"/><path d="M12 12V3.5M12 12l6 6"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  list: svg('<path d="M9 6.5h11M9 12h11M9 17.5h11"/><circle cx="5" cy="6.5" r="1"/><circle cx="5" cy="12" r="1"/><circle cx="5" cy="17.5" r="1"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  sparkle: svg('<path d="M12 3.5l1.8 5 5 1.8-5 1.8-1.8 5-1.8-5-5-1.8 5-1.8z"/><path d="M18.5 15.5l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  download: svg('<path d="M12 4v11M7.5 10.5L12 15l4.5-4.5"/><path d="M4.5 16v2.5A1.5 1.5 0 0 0 6 20h12a1.5 1.5 0 0 0 1.5-1.5V16"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  upload: svg('<path d="M12 15V4M7.5 8.5L12 4l4.5 4.5"/><path d="M4.5 16v2.5A1.5 1.5 0 0 0 6 20h12a1.5 1.5 0 0 0 1.5-1.5V16"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  logout: svg('<path d="M14 4.5H6.5A1.5 1.5 0 0 0 5 6v12a1.5 1.5 0 0 0 1.5 1.5H14"/><path d="M10.5 12H20M16.5 8.5L20 12l-3.5 3.5"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  lock: svg('<rect x="5" y="10.5" width="14" height="10" rx="1.8"/><path d="M8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3"/><path d="M12 14.5v2.5"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  pencil: svg('<path d="M15.5 4.5l4 4L9 19l-4.5 1 1-4.5z"/><path d="M13.5 6.5l4 4"/>'),
  copy: svg('<rect x="8" y="8" width="11" height="12" rx="1.5"/><path d="M5 15.5V5.5A1.5 1.5 0 0 1 6.5 4H15"/>'),
  trash: svg('<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>'),
  refresh: svg('<path d="M20 11a8 8 0 0 0-14.3-4.9L4 8M4 4v4h4M4 13a8 8 0 0 0 14.3 4.9L20 16M20 20v-4h-4"/>'),
  stats: svg('<path d="M4 20h16"/><path d="M6.5 17v-5M10.5 17V7M14.5 17v-7M18.5 17V4.5"/>', "0 0 24 24").replace('stroke-width="1.9"', 'stroke-width="1.6"'),
  book: svg('<path d="M6.5 3.5h11a1.5 1.5 0 0 1 1.5 1.5v14.5a1 1 0 0 1-1 1H6.5A1.5 1.5 0 0 1 5 19V5a1.5 1.5 0 0 1 1.5-1.5z"/><path d="M5 17.5A1.5 1.5 0 0 1 6.5 16H19"/><path d="M9 7.5h6.5M9 10.5h6.5"/>').replace('stroke-width="1.9"', 'stroke-width="1.6"'),
  gear: svg('<circle cx="12" cy="12" r="3"/><path d="M12 2.8l1.6.3.5 2.2 1.5.7 1.9-1.2 1.3 1 1 1.3-1.2 1.9.7 1.5 2.2.5.3 1.6-.3 1.6-2.2.5-.7 1.5 1.2 1.9-1 1.3-1.3 1-1.9-1.2-1.5.7-.5 2.2-1.6.3-1.6-.3-.5-2.2-1.5-.7-1.9 1.2-1.3-1-1-1.3 1.2-1.9-.7-1.5-2.2-.5L2.8 12l.3-1.6 2.2-.5.7-1.5-1.2-1.9 1-1.3 1.3-1 1.9 1.2 1.5-.7.5-2.2z"/>').replace('stroke-width="1.9"', 'stroke-width="1.5"'),
  accounts: svg('<ellipse cx="9" cy="7" rx="6" ry="2.6"/><path d="M3 7v4c0 1.4 2.7 2.6 6 2.6s6-1.2 6-2.6V7"/><path d="M9 13.6v3.8c0 1.4 2.7 2.6 6 2.6s6-1.2 6-2.6v-4c0-1.4-2.7-2.6-6-2.6"/>').replace('stroke-width="1.9"', 'stroke-width="1.6"'),
  more: svg('<circle cx="5.5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="18.5" cy="12" r="1.3" fill="currentColor"/>'),
  cal: (d) => `<svg class="tab-cal" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" aria-hidden="true"><rect x="3.5" y="4.5" width="17" height="16" rx="3"/><path d="M3.5 9h17M8 3v3M16 3v3" stroke-linecap="round"/><text x="12" y="18.2" text-anchor="middle" stroke="none">${d}</text></svg>`,
};

/** Create an element from an HTML string. */
export function h(html) {
  const t = document.createElement("template");
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

const app = () => document.getElementById("app");
export const stack = [];

/**
 * Push a page over the current one.
 * opts: {kind: "push"|"modal", className, html, onMount(el, page), render(page), onClose()}
 * Returns the page object; page.close() pops it.
 */
export function pushPage(opts) {
  const kind = opts.kind || "push";
  const el = h(`<section class="page ${kind} ${opts.tabs ? "tabs" : ""} ${opts.className || ""}">${opts.html || ""}</section>`);
  const below = stack.at(-1)?.el || document.querySelector(".page.root");
  const page = {
    el, opts, kind,
    close: () => popPage(page),
    render: () => opts.render?.(page),
  };
  stack.push(page);
  app().appendChild(el);
  syncDim();
  opts.onMount?.(el, page);
  page.render();
  requestAnimationFrame(() => requestAnimationFrame(() => {
    el.classList.add("in");
    if (kind === "push" && below && !opts.tabs) below.classList.add("under");
  }));
  return page;
}

export function popPage(page = stack.at(-1)) {
  const i = stack.indexOf(page);
  if (i < 0) return;
  stack.splice(i, 1);
  const below = stack.at(-1)?.el || document.querySelector(".page.root");
  page.el.classList.remove("in");
  if (page.kind === "push" && below) below.classList.remove("under");
  page.opts.onClose?.();
  syncDim();
  setTimeout(() => page.el.remove(), 360);
}

/** Dim the tab shell while any page is open (shown as a scrim on desktop only). */
const syncDim = () => document.querySelector(".page.root")?.classList.toggle("dim", stack.length > 0);

export function popAll() { while (stack.length) popPage(); }

/** Re-render every page in the stack (after data changes). */
export function renderStack() { for (const p of stack) p.render(); }

/** Standard header with back/close button. */
export function pageHeader({ title, back = "left", right = "" }) {
  return `<header class="hdr"><div class="hdr-bar">
    <button class="icon-btn hdr-l" data-act="back" aria-label="Back">${back === "close" ? icons.close : icons.left}</button>
    <div class="hdr-title">${title}</div>
    <div class="hdr-r">${right}</div>
  </div></header>`;
}

/**
 * Bottom sheet. opts: {title, html, tall, left, right, onMount(el, sheet), onClose}
 * Returns {el, body, close}.
 */
export function openSheet(opts) {
  const bg = h(`<div class="sheet-bg"></div>`);
  const el = h(`<div class="sheet ${opts.tall ? "tall" : ""}" role="dialog" aria-label="${esc(opts.title || "")}">
    <div class="sheet-h">
      <div>${opts.left ?? `<button class="icon-btn" data-act="sheet-close" aria-label="Close">${icons.close}</button>`}</div>
      <div class="t">${opts.title || ""}</div>
      <div>${opts.right || ""}</div>
    </div>
    <div class="sheet-b">${opts.html || ""}</div>
  </div>`);
  document.body.append(bg, el);
  let closed = false;
  const sheet = {
    el, body: el.querySelector(".sheet-b"),
    setTitle: (t) => { el.querySelector(".sheet-h .t").textContent = t; },
    setLeft: (html) => { el.querySelector(".sheet-h > div").innerHTML = html; },
    close: () => {
      if (closed) return;
      closed = true;
      bg.classList.remove("in"); el.classList.remove("in");
      opts.onClose?.();
      setTimeout(() => { bg.remove(); el.remove(); }, 320);
    },
  };
  bg.addEventListener("click", sheet.close);
  el.addEventListener("click", (e) => { if (e.target.closest("[data-act=sheet-close]")) sheet.close(); });
  opts.onMount?.(el, sheet);
  requestAnimationFrame(() => requestAnimationFrame(() => { bg.classList.add("in"); el.classList.add("in"); }));
  return sheet;
}

/** Confirm dialog as an action sheet. Resolves true/false. */
export function confirmSheet({ title, message = "", ok = "Delete", danger = true }) {
  return new Promise((resolve) => {
    let result = false;
    openSheet({
      title,
      html: `<div class="sheet-pad">${message ? `<p class="muted" style="margin:4px 2px 16px;line-height:1.45">${esc(message)}</p>` : ""}
        <button class="btn block ${danger ? "primary" : "primary"}" data-ok style="${danger ? "--tc:var(--exp)" : ""}">${esc(ok)}</button>
        <button class="btn block ghost" data-act="sheet-close">Cancel</button></div>`,
      onMount: (el, s) => el.querySelector("[data-ok]").addEventListener("click", () => { result = true; s.close(); }),
      onClose: () => resolve(result),
    });
  });
}

/** Single-field prompt sheet. Resolves the string or null. */
export function promptSheet({ title, label = "", value = "", placeholder = "", inputmode = "text", ok = "Save", extra = "" }) {
  return new Promise((resolve) => {
    let result = null;
    openSheet({
      title,
      html: `<form class="sheet-pad">
        ${label ? `<label class="field-lbl">${esc(label)}</label>` : ""}
        <input class="input" name="v" value="${esc(value)}" placeholder="${esc(placeholder)}" inputmode="${inputmode}" autocomplete="off">
        ${extra}
        <button class="btn block primary" style="margin-top:14px">${esc(ok)}</button></form>`,
      onMount: (el, s) => {
        const input = el.querySelector("input");
        setTimeout(() => input.focus(), 350);
        el.querySelector("form").addEventListener("submit", (e) => { e.preventDefault(); result = input.value; s.close(); });
      },
      onClose: () => resolve(result),
    });
  });
}

let toastTimer;
export function toast(msg, ms = 1800) {
  const el = document.getElementById("toast");
  el.textContent = msg;
  el.classList.add("in");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("in"), ms);
}

/** Month switcher markup: ‹ label › with data-act prev/next. */
export const monthSwitcher = (label) =>
  `<div class="month-sw"><button data-act="prev" aria-label="Previous">${icons.left}</button><span class="lbl" data-act="today" role="button">${esc(label)}</span><button data-act="next" aria-label="Next">${icons.right}</button></div>`;
