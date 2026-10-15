// Motion for changes the user asked for (tab, month, mode). Background sync re-renders stay still.

import { num } from "./format.js";

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const KINDS = ["m-fade", "m-next", "m-prev", "m-pop", "m-sweep"];

/** Replay a CSS animation class on `el` (see "Motion" in styles.css). */
export function play(el, kind) {
  if (!el || !kind || reduced.matches) return;
  el.classList.remove(...KINDS);
  void el.offsetWidth; // restart the animation
  el.classList.add(`m-${kind}`);
  const done = (e) => { if (e.target === el) { el.classList.remove(`m-${kind}`); el.removeEventListener("animationend", done); } };
  el.addEventListener("animationend", done);
}

/** Count the strip's amounts up from the values shown before this render. */
export function countUp(wrap, animate) {
  const cells = [...wrap.querySelectorAll("[data-n]")];
  const prev = wrap._shown || [];
  wrap._shown = cells.map((c) => Number(c.dataset.n));
  if (!animate || reduced.matches) return;
  const t0 = performance.now(), ms = 520;
  const ease = (x) => 1 - Math.pow(1 - x, 3);
  const frame = (now) => {
    const k = ease(Math.min((now - t0) / ms, 1));
    cells.forEach((c, i) => {
      if (!c.isConnected) return;
      const to = wrap._shown[i], from = prev[i] ?? 0;
      c.textContent = num(from + (to - from) * k);
    });
    if (k < 1) requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
