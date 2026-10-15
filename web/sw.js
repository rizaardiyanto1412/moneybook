// Moneybook service worker: caches the app shell only.
// API traffic (/api, /mcp) is never intercepted or cached: responses are
// authenticated and the app keeps its own local data cache instead.

const VERSION = "mb-shell-v15";
const SHELL = [
  "/", "/index.html", "/styles.css", "/manifest.webmanifest",
  "/js/app.js", "/js/api.js", "/js/store.js", "/js/format.js", "/js/ui.js", "/js/components.js",
  "/js/importer.js", "/js/mmbak.js", "/js/motion.js",
  "/js/views/trans.js", "/js/views/stats.js", "/js/views/accounts.js", "/js/views/more.js", "/js/views/entry.js",
  "/icons/icon-192.png", "/icons/icon-512.png", "/icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;
  // Network only for the API: never store authenticated responses.
  if (url.pathname.startsWith("/api/") || url.pathname.startsWith("/mcp")) return;

  // App shell: network first (fresh code when online), cache fallback offline.
  event.respondWith((async () => {
    const cache = await caches.open(VERSION);
    try {
      const res = await fetch(req, { cache: "no-cache" });
      if (res.ok && res.type === "basic") cache.put(req.mode === "navigate" ? "/index.html" : req, res.clone());
      return res;
    } catch {
      const hit = await cache.match(req.mode === "navigate" ? "/index.html" : req, { ignoreSearch: true });
      return hit || (req.mode === "navigate" ? cache.match("/index.html") : Response.error());
    }
  })());
});
