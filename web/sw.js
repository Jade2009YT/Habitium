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

const CACHE_VERSION = "habitium-v10";

const SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./app.js",
  "./theme-boot.js",
  "./store.js",
  // Los módulos que app.js importa: sin ellos en la caché, la app abre
  // sin conexión pero se queda a medias al no poder resolver el import.
  "./progression.js",
  "./player.js",
  "./study.js",
  "./seguridad.js",
  "./routines.js",
  "./avisos.js",
  "./ia.js",
  "./nutricion-ia.js",
  "./finanzas-ia.js",
  "./config.js",
  // Si existe la copia local de supabase-js, se cachea. Si no, el
  // cache.add falla en silencio y se usa el CDN de abajo.
  "./vendor/supabase.js",
  "./manifest.json",
  "./icon.png",
];

/** Supabase, que vive en un CDN de fuera.
 *
 *  Va aparte de SHELL y se cachea EN LA INSTALACIÓN, no al vuelo. Sin
 *  esto la app no arranca sin conexión: app.js lo importa de forma
 *  estática, y un import que no se resuelve deja la página en la
 *  pantalla de carga para siempre. Se descubrió probando la app
 *  instalada en modo avión — con la red puesta no se nota nunca.
 *
 *  Lo suyo de verdad es descargarlo al proyecto (ver README → "vendorizar
 *  supabase-js") y quitar esta dependencia entera. Mientras siga aquí,
 *  esto es el seguro. */
const CDN_SUPABASE = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm";

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) =>
      // addAll falla entero si un solo archivo falla; se piden de uno en
      // uno para que la instalación no se caiga por algo secundario.
      Promise.all(
        [...SHELL, CDN_SUPABASE].map((url) =>
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

  if (isCDN) {
    // Versión fija en la URL: lo cacheado nunca queda viejo, así que la
    // caché manda y la red es solo el respaldo de la primera vez.
    event.respondWith(
      caches.match(request).then((cached) =>
        cached ||
        fetch(request).then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_VERSION).then((c) => c.put(request, copy));
          }
          return response;
        })
      )
    );
    return;
  }

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

// ── Pulsar un aviso de rutina ───────────────────────────────────────
//
// Sin esto, tocar la notificación no hace nada (o abre una pestaña nueva
// en blanco), que es la forma más rápida de que dejen de tocarse.
//
// Lo que hace: si Habitium ya está abierta en alguna pestaña, la trae al
// frente en vez de abrir otra — nadie quiere seis copias de su app. Y le
// manda un mensaje para que salte a Rutinas.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((abiertas) => {
      for (const cliente of abiertas) {
        if (cliente.url.includes("/index.html") || cliente.url.endsWith("/")) {
          cliente.postMessage({ tipo: "ir-a-rutinas", datos: event.notification.data });
          return cliente.focus();
        }
      }
      return self.clients.openWindow("./index.html?vista=routines");
    })
  );
});
