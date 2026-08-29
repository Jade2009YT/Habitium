// sw.js — service worker de Habitium.
//
// Su único trabajo es que la app arranque al instante y siga abriendo
// sin conexión (o con el NAS apagado). Los DATOS no pasan por aquí: de
// eso se encarga store.js con IndexedDB. Aquí solo se guardan los
// archivos de la app — HTML, CSS, JS, icono.
//
// Estrategia por tipo de petición:
//
//   · Navegación (abrir la app): red primero, caché si falla. Así una
//     versión nueva subida al NAS se coge en cuanto hay red, en vez de
//     quedarse pegada la vieja para siempre.
//   · Archivos propios (css/js/png): se sirve la caché al instante y se
//     refresca por detrás ("stale-while-revalidate"). Arranque rápido, y
//     la versión nueva entra en la siguiente carga.
//   · La librería de Supabase (CDN): caché primero, es una versión fija.
//   · La API de Supabase: NUNCA se cachea. Son datos, y cachearlos daría
//     respuestas viejas silenciosamente. Si no hay red, la petición falla
//     y store.js tira de IndexedDB, que es lo correcto.
//
// Al cambiar los archivos de la app, sube también este archivo con
// CACHE_VERSION incrementado — así se limpian las cachés antiguas.

const CACHE_VERSION = "habitium-v2";

const SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./store.js",
  "./config.js",
  "./manifest.webmanifest",
  "./icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) =>
      // addAll falla entero si un solo archivo falla; se piden de uno en
      // uno para que la instalación no se caiga por algo secundario.
      Promise.all(
        SHELL.map((url) =>
          cache.add(url).catch((error) => console.warn("SW: no se pudo cachear", url, error))
        )
      )
    )
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(names.filter((n) => n !== CACHE_VERSION).map((n) => caches.delete(n)))
      )
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Datos: siempre a la red. Nunca se cachean.
  if (url.hostname.endsWith(".supabase.co")) return;

  // Abrir la app: red primero para coger actualizaciones.
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_VERSION).then((c) => c.put("./index.html", copy));
          return response;
        })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  const sameOrigin = url.origin === self.location.origin;
  const isCDN = url.hostname === "cdn.jsdelivr.net";
  if (!sameOrigin && !isCDN) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_VERSION).then((c) => c.put(request, copy));
          }
          return response;
        })
        .catch(() => cached);

      // Caché al instante si la hay; si no, lo que traiga la red.
      return cached || network;
    })
  );
});
