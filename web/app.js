// Habitium web — interfaz.
//
// Ya NO habla con Supabase directamente: todo pasa por store.js, que
// guarda en IndexedDB y sincroniza por detrás. Esto es lo que hace que
// la app arranque al instante, funcione sin conexión, y muestre lo mismo
// que el iPhone en cuanto haya red — la misma arquitectura que
// SwiftData + CloudSyncService en iOS.
//
// Consecuencia práctica para el código de abajo: las funciones de carga
// son síncronas contra datos ya presentes, y cualquier escritura repinta
// al momento (optimista) sin esperar al servidor. store.onChange() se
// encarga de volver a pintar cuando llega algo nuevo de la nube.

// Versión EXACTA, no "@2".
//
// Con "@2" el CDN sirve la última 2.x que haya en cada momento: el día
// que alguien publique una versión con código malicioso —o le roben la
// cuenta a quien publica— ese código se ejecuta en esta página con
// acceso completo a la sesión y a lo que haya en localStorage, sin que
// nadie toque este repositorio. Anclar la versión no elimina el riesgo,
// pero lo congela en algo que se puede revisar.
//
// Lo ideal es no depender del CDN en absoluto. Para hacerlo, en tu Mac:
//
//   mkdir -p web/vendor && curl -o web/vendor/supabase.js \
//     "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm"
//
// Y ya está: no hay que tocar este archivo. La carga de abajo prueba
// primero la copia local y solo va al CDN si no la encuentra.
//
// ── Por qué esto es un import dinámico y no uno normal ─────────────
//
// Con un `import` estático, si la dirección no se resuelve el módulo
// ENTERO no se evalúa: no se ejecuta una sola línea de la app, no salta
// ningún error visible, y la pantalla se queda en "Cargando…" para
// siempre. Eso pasa la primera vez que abres la app sin cobertura, con
// el CDN caído o con un bloqueador de anuncios agresivo — y parece que
// la app está rota sin decir por qué.
//
// Se descubrió probando la app instalada en modo avión. Con la red
// puesta no se nota nunca.
import * as store from "./store.js";
import * as player from "./player.js";
import * as prog from "./progression.js";
import * as study from "./study.js";
import * as seg from "./seguridad.js";
import * as rut from "./routines.js";
import * as avisos from "./avisos.js";
import * as ia from "./ia.js";
import * as nutri from "./nutricion-ia.js";
import * as fin from "./finanzas-ia.js";

const { createClient } = await (async () => {
  try {
    // La copia local manda: si está, la app no depende de ninguna red
    // ajena ni para arrancar ni para funcionar. Da un 404 en la consola
    // cuando no existe, y es a propósito: el coste de ese 404 es menor
    // que el de arrastrar una dependencia externa sin saberlo.
    return await import("./vendor/supabase.js");
  } catch (e) {
    return await import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.58.0/+esm");
  }
})();

const cfg = window.HABITIUM_CONFIG;
const isConfigured =
  cfg &&
  typeof cfg.SUPABASE_URL === "string" &&
  typeof cfg.SUPABASE_ANON_KEY === "string" &&
  cfg.SUPABASE_URL.startsWith("http") &&
  !cfg.SUPABASE_URL.includes("tu-proyecto") &&
  !cfg.SUPABASE_ANON_KEY.includes("tu_clave");

const $ = (id) => document.getElementById(id);

if (!isConfigured) {
  $("boot").hidden = true;
  $("config-error").hidden = false;
  throw new Error("Habitium: falta web/config.js o sigue con los valores de ejemplo.");
}

/** ¿Se marcó "este no es mi dispositivo" la última vez?
 *
 *  Tiene que leerse ANTES de crear el cliente, porque de ello depende
 *  dónde se guarda la sesión, y eso no se puede cambiar después. */
const dispositivoAjeno = (() => {
  try { return sessionStorage.getItem("habitium.shared") === "1"; } catch (e) { return false; }
})();

// En un dispositivo compartido —el iPad del colegio, el portátil de un
// amigo— la sesión va a sessionStorage en vez de a localStorage.
//
// La diferencia es todo: localStorage sobrevive a cerrar la pestaña, al
// reinicio del navegador y al del aparato, así que quien lo coja después
// abre la app y está DENTRO de tu cuenta sin saber tu contraseña.
// sessionStorage muere al cerrar la pestaña. Nadie se acuerda de darle a
// "cerrar sesión" cuando suena el timbre.
const supabase = createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
  auth: {
    storage: dispositivoAjeno ? window.sessionStorage : window.localStorage,
    persistSession: true,
    autoRefreshToken: true,
    // El token no viaja en la URL: si llegara ahí acabaría en el
    // historial del navegador y en los registros de cualquier servidor
    // por el que pase el enlace.
    detectSessionInUrl: true,
    flowType: "pkce",
  },
});

store.configure(supabase, async () => (await supabase.auth.getUser()).data?.user?.id ?? null);

// El service worker es opcional: si el navegador no lo soporta o la
// página se sirve por http://, la app funciona igual, solo que sin
// arranque instantáneo ni modo sin conexión.
if ("serviceWorker" in navigator) {
  const registrar = () =>
    navigator.serviceWorker.register("./sw.js").catch((e) => console.warn("SW:", e));

  // Ojo con esperar a `load` sin más: este módulo tiene un `await` de
  // nivel superior (la carga de supabase-js), así que para cuando se
  // llega aquí el evento `load` puede haber disparado YA — y un listener
  // de `load` añadido tarde no se ejecuta nunca. El service worker no se
  // registraba, y con él se iban el arranque instantáneo y el modo sin
  // conexión, sin un solo error en consola.
  if (document.readyState === "complete") registrar();
  else window.addEventListener("load", registrar, { once: true });
}

// ── Utilidades ──────────────────────────────────────────────────────

const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
};
const startOfTomorrow = () => {
  const d = startOfToday();
  d.setDate(d.getDate() + 1);
  return d;
};
const startOfMonth = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1);
};
const startOfNextMonth = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() + 1, 1);
};
const nowISO = () => new Date().toISOString();

const inRange = (iso, from, to) => {
  const t = new Date(iso).getTime();
  return t >= from.getTime() && t < to.getTime();
};
const sameDay = (iso, day) => {
  const d = new Date(iso);
  d.setHours(0, 0, 0, 0);
  return d.getTime() === day.getTime();
};

let currencyCode = "EUR";
const money = (v) =>
  new Intl.NumberFormat("es-ES", {
    style: "currency",
    currency: currencyCode,
    maximumFractionDigits: 2,
  }).format(v ?? 0);

const timeOf = (iso) =>
  new Date(iso).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
const dayOf = (iso) =>
  new Date(iso).toLocaleDateString("es-ES", { day: "numeric", month: "short" });
const minutesToTime = (m) =>
  `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );

const byDateDesc = (a, b) => new Date(b.date) - new Date(a.date);

/** Un vacío que dice qué falta y cómo llenarlo.
 *
 *  Antes cada lista vacía era una caja gris con una frase resignada
 *  ("Aún no hay nada"). Eso deja a quien abre la app por primera vez
 *  mirando cinco cajas grises sin saber por dónde empezar, que es
 *  justo el momento en que se decide si la vuelve a abrir. */
function emptyState(icon, title, hint = "") {
  return `<li class="empty">
            <span class="empty-icon" aria-hidden="true">${icon}</span>
            <span class="empty-title">${esc(title)}</span>
            ${hint ? `<span class="empty-hint">${esc(hint)}</span>` : ""}
          </li>`;
}


// ── Indicador de sincronización ─────────────────────────────────────

function renderSyncBanner() {
  const b = $("sync-banner");
  const { online, pending, lastError } = store.syncState;

  if (!online) {
    b.className = "banner is-info";
    b.textContent =
      pending > 0
        ? `Sin conexión · ${pending} cambio${pending === 1 ? "" : "s"} se subirá${pending === 1 ? "" : "n"} al volver`
        : "Sin conexión · puedes seguir usando la app";
    b.hidden = false;
    return;
  }

  if (lastError) {
    b.className = "banner";
    b.textContent = `Problema al sincronizar: ${lastError}`;
    b.hidden = false;
    return;
  }

  if (pending > 0) {
    b.className = "banner is-info";
    b.textContent = `Subiendo ${pending} cambio${pending === 1 ? "" : "s"}…`;
    b.hidden = false;
    return;
  }

  b.hidden = true;
}

// ── Autenticación ───────────────────────────────────────────────────

let authMode = "signin";

function setAuthMode(mode) {
  authMode = mode;
  $("tab-signin").classList.toggle("is-active", mode === "signin");
  $("tab-signup").classList.toggle("is-active", mode === "signup");
  $("auth-submit").textContent = mode === "signin" ? "Iniciar sesión" : "Crear cuenta";
  $("auth-password").autocomplete = mode === "signin" ? "current-password" : "new-password";
  $("forgot-password").hidden = mode !== "signin";
  if ($("auth-strength")) $("auth-strength").hidden = true;
  setAuthMessage("");
  prepararRegistro();
}

function setAuthMessage(text, ok = false) {
  const el = $("auth-message");
  el.textContent = text;
  el.classList.toggle("is-ok", ok);
}

$("tab-signin").addEventListener("click", () => setAuthMode("signin"));
$("tab-signup").addEventListener("click", () => setAuthMode("signup"));

// La barrita de fuerza, mientras se escribe. Solo aparece al crear la
// cuenta: enseñársela a quien ya tiene una es decirle que la suya es mala
// cuando ya no puede hacer nada al respecto desde ahí.
$("auth-password").addEventListener("input", () => {
  const barra = $("auth-strength");
  if (!barra) return;
  if (authMode !== "signup" || !$("auth-password").value) {
    barra.hidden = true;
    return;
  }
  const { nivel, texto } = seg.fuerzaContrasena($("auth-password").value, $("auth-email").value);
  barra.hidden = false;
  barra.dataset.nivel = String(nivel);
  $("auth-strength-text").textContent = texto;
});

// Si el registro está por invitación, el campo del código aparece solo.
// Si está cerrado, ni se deja intentarlo.
async function prepararRegistro() {
  const modo = await seg.modoDeRegistro(supabase);
  const campo = $("auth-invite-field");
  if (campo) campo.hidden = !(authMode === "signup" && modo === "invitacion");

  if (authMode === "signup" && modo === "cerrado") {
    $("auth-submit").disabled = true;
    setAuthMessage("El registro está cerrado ahora mismo. Si ya tienes cuenta, inicia sesión.");
  } else {
    $("auth-submit").disabled = false;
  }
}

$("auth-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const email = $("auth-email").value.trim();
  const password = $("auth-password").value;
  const submit = $("auth-submit");

  // Solo al crear la cuenta: a quien ya tiene una con la contraseña
  // antigua no se le puede dejar fuera de su propia app.
  if (authMode === "signup") {
    const problema = seg.problemaContrasena(password, email);
    if (problema) return setAuthMessage(problema);
  }

  // El freno a los intentos a lo bruto. Va ANTES de tocar la red: si hay
  // que esperar, ni se molesta al servidor.
  if (authMode === "signin") {
    const espera = seg.esperaPendiente(email);
    if (espera > 0) {
      return setAuthMessage(
        espera >= 60
          ? `Demasiados intentos. Espera ${Math.ceil(espera / 60)} minuto${espera >= 120 ? "s" : ""}.`
          : `Demasiados intentos. Espera ${espera} segundo${espera === 1 ? "" : "s"}.`
      );
    }
  }

  // Se recuerda la elección ANTES de entrar: al recargar, el cliente ya
  // sabe dónde tiene que buscar la sesión.
  try {
    if ($("auth-shared").checked) sessionStorage.setItem("habitium.shared", "1");
    else sessionStorage.removeItem("habitium.shared");
  } catch (err) {}

  submit.disabled = true;
  setAuthMessage("");

  const codigo = seg.limpiarCodigo($("auth-invite")?.value);
  const { data, error } =
    authMode === "signup"
      ? await supabase.auth.signUp({
          email,
          password,
          // Esto viaja al portero del registro (el trigger de auth.users).
          // Quien lo quite desde el navegador no se cuela: lo único que
          // consigue es que el servidor le diga que no.
          options: codigo ? { data: { invite_code: codigo } } : undefined,
        })
      : await supabase.auth.signInWithPassword({ email, password });

  submit.disabled = false;

  if (error) {
    if (authMode === "signin") seg.apuntarFallo(email);
    return setAuthMessage(seg.mensajeDeError(error));
  }

  seg.limpiarFallos(email);

  if (authMode === "signup" && !data.session) {
    setAuthMessage(`Te hemos enviado un enlace a ${email}. Ábrelo y vuelve aquí.`, true);
  }
});

$("forgot-password").addEventListener("click", async () => {
  const email = $("auth-email").value.trim();
  if (!email) return setAuthMessage("Escribe tu correo primero.");
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.href,
  });
  // Da igual si el correo existe o no: la respuesta es siempre la misma.
  // Contestar "ese correo no está registrado" sería regalar una forma de
  // averiguar quién tiene cuenta aquí.
  setAuthMessage(
    error && /rate limit|too many/i.test(error.message ?? "")
      ? seg.mensajeDeError(error)
      : "Si hay una cuenta con ese correo, te llegará un enlace en un minuto.",
    true
  );
});

// ── El segundo paso, al entrar ──────────────────────────────────────
//
// Cuando la cuenta tiene verificación en dos pasos, Supabase da una
// sesión "a medias" (aal1) en cuanto la contraseña es correcta. Con esa
// sesión NO se pueden leer datos protegidos, pero la app tiene que
// enterarse y pedir el código en vez de enseñar la pantalla de inicio.

function mostrarSegundoPaso() {
  $("boot").hidden = true;
  $("app").hidden = true;
  $("auth-screen").hidden = false;
  $("auth-form").hidden = true;
  $("auth-tabs").hidden = true;
  $("forgot-password").hidden = true;
  $("mfa-form").hidden = false;
  setAuthMessage("");
  $("mfa-code").value = "";
  setTimeout(() => $("mfa-code").focus(), 50);
}

function ocultarSegundoPaso() {
  $("mfa-form").hidden = true;
  $("auth-form").hidden = false;
  $("auth-tabs").hidden = false;
  $("forgot-password").hidden = authMode !== "signin";
}

$("mfa-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const boton = $("mfa-submit");
  const codigo = $("mfa-code").value;

  // El mismo freno que en la contraseña: seis cifras son un millón de
  // combinaciones, y sin freno un script las prueba todas.
  const espera = seg.esperaPendiente("mfa");
  if (espera > 0) return setAuthMessage(`Demasiados intentos. Espera ${espera} segundos.`);

  boton.disabled = true;
  setAuthMessage("");
  try {
    await seg.verificarSegundoFactor(supabase, codigo);
    seg.limpiarFallos("mfa");
    ocultarSegundoPaso();
    await showApp();
  } catch (error) {
    seg.apuntarFallo("mfa");
    setAuthMessage(seg.mensajeDeError(error));
    $("mfa-code").value = "";
  } finally {
    boton.disabled = false;
  }
});

$("mfa-cancel").addEventListener("click", async () => {
  ocultarSegundoPaso();
  await supabase.auth.signOut();
});

async function doSignOut() {
  // Sin cuenta, "Salir" solo vuelve a la pantalla de entrada. Los datos
  // se quedan donde están: son de este dispositivo, no de una sesión, y
  // borrarlos aquí sería tirar el trabajo de alguien que solo quería
  // ver qué hay detrás del botón.
  if (store.esSoloLocal()) {
    salirDeModoLocal();
    return;
  }

  // Con cuenta sí se borra lo local: en un dispositivo compartido (el
  // iPad del cole) los datos de una cuenta no deben quedar accesibles a
  // la siguiente.
  await store.wipe();

  // Y la clave de IA. Si se quedara, la siguiente persona que entrara
  // con SU cuenta seguiría gastando la de quien la dejó puesta — y la
  // factura le llegaría al primero.
  for (const proveedor of ["openai", "anthropic"]) {
    try { localStorage.removeItem(`${AI_KEY}.${proveedor}`); } catch (e) {}
    try { sessionStorage.removeItem(`${AI_KEY}.${proveedor}`); } catch (e) {}
  }

  await supabase.auth.signOut();
}
$("sign-out").addEventListener("click", doSignOut);
$("sign-out-2").addEventListener("click", doSignOut);

// ── Modo sin cuenta ─────────────────────────────────────────────────
//
// Habitium entera, funcionando contra el navegador y nada más: sin
// registro, sin servidor, sin que nadie te invite. Es lo que hace que
// puedas pasarle la app a un amigo con un enlace y que la use en su
// Android el mismo día.
//
// Por dentro no cambia casi nada, y eso es lo bueno: la app SIEMPRE ha
// guardado todo en IndexedDB y Supabase solo servía para copiarlo entre
// tus dispositivos. Quitar Supabase de la ecuación es no llamar a
// store.configure().
//
// Lo que sí hay que cuidar es que no sea un callejón sin salida: quien
// use esto tres meses y luego quiera el portátil tiene que poder crear
// una cuenta SIN perder nada (ver migrarANube en store.js). Sin esa
// salida, el modo local sería una trampa amable.

/** Un aviso en la franja de arriba. Se va solo a los seis segundos: es
 *  para decir algo, no para quedarse. */
function banner(texto, clase = "is-info", segundos = 6) {
  const b = $("sync-banner");
  if (!b) return;
  b.className = `banner ${clase}`.trim();
  b.textContent = texto;
  b.hidden = false;
  clearTimeout(banner._reloj);
  banner._reloj = setTimeout(() => { b.hidden = true; }, segundos * 1000);
}

const CLAVE_LOCAL = "habitium.sincuenta";

function enModoLocal() {
  try {
    return localStorage.getItem(CLAVE_LOCAL) === "1";
  } catch (e) {
    return false;
  }
}

function marcarModoLocal(activo) {
  try {
    if (activo) localStorage.setItem(CLAVE_LOCAL, "1");
    else localStorage.removeItem(CLAVE_LOCAL);
  } catch (e) {}
}

/** Entrar sin cuenta. */
async function usarSinCuenta() {
  marcarModoLocal(true);
  store.configureLocal();
  await showApp({ local: true });
}

$("use-local")?.addEventListener("click", usarSinCuenta);

/** Salir del modo local. No borra nada: los datos siguen en el
 *  dispositivo, y si vuelves a entrar sin cuenta están donde estaban. */
function salirDeModoLocal() {
  marcarModoLocal(false);
  showAuth();
}

// ── De sin cuenta a con cuenta ──────────────────────────────────────

$("local-to-account")?.addEventListener("click", () => {
  // Se marca que hay datos locales esperando. En cuanto haya sesión,
  // continuarSesion() los sube. Se hace así y no aquí mismo porque
  // crear la cuenta pasa por el correo de confirmación: entre pulsar el
  // botón y tener sesión pueden pasar minutos y un cambio de pestaña.
  try { sessionStorage.setItem("habitium.migrar", "1"); } catch (e) {}
  marcarModoLocal(false);
  showAuth();
  setAuthMode("signup");
  setAuthMessage("Crea tu cuenta y subiremos lo que ya tienes apuntado.", true);
});

/** Sube lo local a la cuenta recién creada. */
async function migrarSiTocaba() {
  let tocaba = false;
  try {
    tocaba = sessionStorage.getItem("habitium.migrar") === "1";
    sessionStorage.removeItem("habitium.migrar");
  } catch (e) {}
  if (!tocaba) return;

  try {
    const filas = await store.migrarANube();
    if (filas > 0) {
      banner(`Listo: ${filas} cosas tuyas están ya en tu cuenta.`, "is-ok");
    }
  } catch (error) {
    console.warn("migrar:", error);
    banner("No se han podido subir tus datos. Siguen aquí: pulsa el botón de sincronizar.", "");
  }
}

// ── Descargar los datos ─────────────────────────────────────────────
//
// En modo local no hay copia de seguridad en ningún sitio: si el móvil
// se pierde o alguien borra los datos del navegador, se va todo. Poder
// bajarse un archivo es el mínimo honesto cuando la app te dice "esto
// solo está aquí".

$("local-export")?.addEventListener("click", async () => {
  const estado = $("local-status");
  estado.textContent = "Preparando…";
  try {
    const datos = {};
    for (const tabla of [...store.TABLES, ...store.SINGLETONS]) {
      datos[tabla] = await store.all(tabla);
    }

    const blob = new Blob([JSON.stringify({ version: 1, fecha: nowISO(), datos }, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `habitium-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    // Sin esto el blob se queda en memoria hasta recargar la página.
    setTimeout(() => URL.revokeObjectURL(url), 1000);

    const total = Object.values(datos).reduce((s, v) => s + v.length, 0);
    estado.textContent = `Descargado: ${total} cosas.`;
  } catch (error) {
    estado.textContent = "No se ha podido descargar.";
  }
});

// ── Navegación ──────────────────────────────────────────────────────

const NAV = [
  { id: "home", label: "Inicio", icon: "🏠" },
  { id: "progress", label: "Progreso", icon: "🏆" },
  { id: "routines", label: "Rutinas", icon: "🔁" },
  { id: "study", label: "Estudios", icon: "🎓" },
  { id: "nutrition", label: "Nutrición", icon: "🍎" },
  { id: "planner", label: "Agenda", icon: "📅" },
  { id: "finance", label: "Finanzas", icon: "💶" },
  { id: "habits", label: "Hábitos", icon: "✅" },
  { id: "medication", label: "Medicación", icon: "💊" },
  { id: "settings", label: "Ajustes", icon: "⚙️" },
];

// La barra del móvil no puede con diez destinos sin quedar ilegible.
// Finanzas, Medicación, Hábitos y Ajustes se alcanzan desde las tarjetas
// de Inicio, y Progreso desde la píldora de nivel de la cabecera.
//
// Rutinas entra en la barra y Hábitos sale: una rutina se toca cuatro
// veces cada mañana, con el móvil en la mano y medio dormido, mientras
// que a Hábitos se entra una vez al día. Quien decide qué va en la barra
// es cuántas veces al día hay que llegar ahí rápido, no la importancia.
const MOBILE_TABS = ["home", "routines", "study", "nutrition", "planner"];

function buildNav() {
  $("side-nav").innerHTML = NAV.map(
    (n) => `<button class="side-item" data-view="${n.id}" type="button" role="tab">
              <span aria-hidden="true">${n.icon}</span>${n.label}
            </button>`
  ).join("");

  $("tabbar").innerHTML = NAV.filter((n) => MOBILE_TABS.includes(n.id))
    .map(
      (n) => `<button class="tab" data-view="${n.id}" type="button" role="tab">
                <span aria-hidden="true">${n.icon}</span>${n.label}
              </button>`
    )
    .join("");

  document.querySelectorAll("[data-view]").forEach((el) => {
    el.addEventListener("click", () => go(el.dataset.view));
    // Las tarjetas son <article role="button">, no <button>, así que el
    // teclado no las activa solo.
    if (el.getAttribute("role") === "button" && el.tagName !== "BUTTON") {
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          go(el.dataset.view);
        }
      });
    }
  });
}

let currentView = "home";

function go(view) {
  currentView = view;
  NAV.forEach((n) => ($(`view-${n.id}`).hidden = n.id !== view));
  document.querySelectorAll(".side-item").forEach((el) =>
    el.classList.toggle("is-active", el.dataset.view === view)
  );
  document.querySelectorAll(".tab").forEach((el) =>
    el.classList.toggle("is-active", el.dataset.view === view)
  );
  // En Inicio la barra saluda en vez de repetir "Inicio", que es lo que
  // acabas de pulsar. En el resto sí manda el nombre de la sección.
  const entrada = NAV.find((n) => n.id === view);
  $("topbar-title").textContent = view === "home" ? greeting() : (entrada?.label ?? "");
  $("hero-emoji").textContent = entrada?.icon ?? "🏠";
  refrescarFab();
  window.scrollTo({ top: 0 });
  render();
}

/** "Buenos días" / "Buenas tardes" / "Buenas noches", con el nombre si
 *  lo sabemos. El corte de las 21:00 y no de medianoche: a las once de
 *  la noche nadie considera que sea "por la tarde". */
function greeting() {
  const h = new Date().getHours();
  const saludo = h < 6 ? "Buenas noches" : h < 13 ? "Buenos días" : h < 21 ? "Buenas tardes" : "Buenas noches";
  return displayName ? `${saludo}, ${displayName}` : saludo;
}

/** El nombre a mostrar: lo que haya antes de la @ del correo, con la
 *  primera en mayúscula. No es el nombre real, pero "Buenas tardes,
 *  Rodrigo" se lee mucho mejor que el correo entero en una cabecera. */
let displayName = "";
async function setDisplayName(email) {
  const guardado = (await store.getSingleton("user_settings"))?.display_name;
  if (guardado && guardado.trim()) {
    displayName = guardado.trim().split(" ")[0];
    return;
  }
  // Sin nombre guardado se saca del correo, quitando los números: hay
  // correos que son el nombre repetido y una cifra, y eso en una
  // cabecera queda fatal.
  const base = String(email ?? "").split("@")[0].replace(/[._-]+/g, " ").replace(/\d+/g, "").trim();
  const primeraPalabra = base.split(" ")[0] ?? "";
  displayName = primeraPalabra
    ? primeraPalabra.charAt(0).toUpperCase() + primeraPalabra.slice(1).toLowerCase()
    : "";
}

/** Nivel y racha en la cabecera. Se repinta con cada cambio, así que
 *  subir de nivel se ve ahí arriba sin tener que ir a Progreso. */
async function renderTopbarChip() {
  const profile = await player.profile();
  const racha = profile.login_streak ?? 0;

  $("chip-level").textContent = prog.levelForTotalXP(profile.total_xp);
  $("chip-streak-n").textContent = racha;
  // Sin racha, la llama se apaga en vez de desaparecer: que el hueco no
  // baile, pero que tampoco parezca que tienes una racha de cero.
  $("chip-streak").classList.toggle("is-off", racha === 0);
  $("topbar-chip").title = `Nivel ${prog.levelForTotalXP(profile.total_xp)} · ${racha} día${racha === 1 ? "" : "s"} seguidos`;
}

/** Repinta la vista activa desde los datos locales. */
async function render() {
  renderSyncBanner();
  renderTopbarChip().catch(() => {});
  await {
    home: loadHome,
    progress: loadProgress,
    study: loadStudy,
    routines: loadRoutines,
    nutrition: loadNutrition,
    planner: loadPlanner,
    finance: loadFinance,
    habits: loadHabits,
    medication: loadMedication,
    settings: loadSettings,
  }[currentView]?.();
}

store.onChange(render);

$("refresh").addEventListener("click", () => store.sync());

/** Cablea todos los botones .delete de una lista contra una tabla. */
function wireDelete(list, table) {
  list.querySelectorAll("[data-del]").forEach((btn) => {
    btn.addEventListener("click", () => store.remove(table, btn.dataset.del));
  });
}

// ── Nutrición ───────────────────────────────────────────────────────

const MEALS = {
  breakfast: { name: "Desayuno", icon: "🌅" },
  lunch: { name: "Almuerzo", icon: "☀️" },
  dinner: { name: "Cena", icon: "🌙" },
  snack: { name: "Snack", icon: "🥕" },
};

const todaysFood = async () =>
  (await store.all("food_entries"))
    .filter((e) => inRange(e.date, startOfToday(), startOfTomorrow()))
    .sort((a, b) => new Date(a.date) - new Date(b.date));

const nutritionGoal = () => store.getSingleton("nutrition_goals");

/** Guardar el objetivo diario. Existe como función propia porque ahora
 *  hay dos caminos que llegan aquí —el formulario de Ajustes y el
 *  cuestionario con IA— y los dos tienen que escribir lo mismo. */
const saveNutritionGoal = (campos) => store.putSingleton("nutrition_goals", campos);

// ── Nutrición con IA ────────────────────────────────────────────────
//
// Tres cosas, y las tres necesitan que haya una clave configurada:
//
//   1. El objetivo diario lo calcula la IA a partir de un cuestionario.
//   2. Una foto de la comida se convierte en calorías y macros.
//   3. "¿Qué como ahora?" mira lo que llevas hoy y lo que te queda.
//
// Sin clave, la sección no se abre: se enseña el portero. Es una decisión
// dura a propósito — media sección funcionando a medias, con el objetivo
// puesto a ojo, no es lo que se quería construir.
//
// El cálculo y el cerrojo de seguridad viven en nutricion-ia.js y están
// probados; aquí solo se pinta y se guarda.

/** Las respuestas del cuestionario. Van en localStorage y NO en la nube:
 *  son datos de salud (peso, edad, sexo) y solo hacen falta para calcular
 *  el objetivo, que sí se sincroniza. Lo que viaja es el resultado, no
 *  la ficha médica. */
const CLAVE_QUIZ = "habitium.nutricion.perfil";

function perfilNutricion() {
  try {
    return JSON.parse(localStorage.getItem(CLAVE_QUIZ) ?? "null");
  } catch (e) {
    return null;
  }
}

function guardarPerfil(datos) {
  try { localStorage.setItem(CLAVE_QUIZ, JSON.stringify(datos)); } catch (e) {}
}

/** El estado del cuestionario mientras se está contestando.
 *
 *  `forzado` es "el usuario ha pulsado Recalcular". Lo de "hay que
 *  enseñar el cuestionario porque todavía no hay objetivo" NO se guarda
 *  aquí: se deduce en cada pintada. Mezclar las dos cosas en una sola
 *  bandera hacía que un pintado tardío reabriera el cuestionario encima
 *  del plan recién calculado. */
let quiz = { paso: 0, respuestas: {}, forzado: false, cargado: false };

/** Contador de generación, contra los pintados solapados.
 *
 *  loadNutrition es async y puede estar corriendo varias veces a la vez:
 *  guardar el objetivo dispara store.onChange(render) mientras
 *  calcularObjetivo va por la mitad. Cada copia lee el estado en un
 *  instante distinto, y el que TERMINA el último gana — que no es el que
 *  empezó el último. Quien vuelve de sus awaits y ve que ya no es el
 *  último, se calla. */
let generacionNutricion = 0;

async function loadNutrition() {
  const generacion = ++generacionNutricion;
  const conClave = ia.hayClave();
  const perfil = perfilNutricion();
  const goal = await nutritionGoal();

  // Mientras se esperaba al disco ha entrado otro pintado con datos más
  // nuevos. Pintar ahora sería poner lo viejo encima de lo nuevo.
  if (generacion !== generacionNutricion) return;

  // El portero. Sin clave no hay sección: ni cuestionario, ni listas, ni
  // el formulario de añadir a mano — porque el objetivo contra el que se
  // comparan esas calorías no existiría.
  $("nutrition-gate").hidden = conClave;
  for (const id of ["nutrition-ai-tools", "food-form", "weight-form"]) {
    $(id).hidden = !conClave;
  }
  $("food-list").hidden = !conClave;
  document.querySelector("#view-nutrition .section-title").hidden = !conClave;

  if (!conClave) {
    $("nutrition-quiz").hidden = true;
    $("nutrition-plan").hidden = true;
    return;
  }

  // Con clave pero sin haber contestado nunca: el cuestionario. Se
  // DEDUCE, no se guarda en una bandera: así un pintado tardío no puede
  // reabrirlo después de haberlo terminado.
  const faltaPerfil = !perfil || !goal;
  const tocaQuiz = quiz.forzado || faltaPerfil;

  $("nutrition-quiz").hidden = !tocaQuiz;
  $("nutrition-plan").hidden = tocaQuiz;

  if (tocaQuiz) {
    // Cargar las respuestas previas se hace UNA vez. Si se hiciera en
    // cada pintada, escribir la edad y que llegara un sync te borraría
    // lo que estabas escribiendo.
    if (!quiz.cargado) empezarQuiz(perfil);
    pintarQuiz();
    return;
  }

  pintarPlan(goal, perfil);
  await pintarComidasDelDia();
}

$("nutrition-gate-go").addEventListener("click", () => go("settings"));

// ── El cuestionario ─────────────────────────────────────────────────

function empezarQuiz(perfilPrevio, { forzado = false } = {}) {
  // Se arranca con lo que ya hubiera contestado: recalcular el objetivo
  // porque has cambiado de peso no debería obligarte a repetir la edad.
  quiz = { paso: 0, respuestas: { ...(perfilPrevio ?? {}) }, forzado, cargado: true };
}

function pintarQuiz() {
  const pregunta = nutri.PREGUNTAS[quiz.paso];
  if (!pregunta) return;

  const total = nutri.PREGUNTAS.length;
  $("quiz-bar").style.width = `${Math.round((quiz.paso / total) * 100)}%`;
  $("quiz-count").textContent = `${quiz.paso + 1} de ${total}`;
  $("quiz-back").disabled = quiz.paso === 0;

  const valor = quiz.respuestas[pregunta.id] ?? "";
  const ultima = quiz.paso === total - 1;
  $("quiz-next").textContent = ultima ? "Calcular mi objetivo" : "Siguiente";

  $("quiz-body").innerHTML = `
    <h2 class="quiz-question">${esc(pregunta.texto)}</h2>
    ${pregunta.ayuda ? `<p class="muted sm">${esc(pregunta.ayuda)}</p>` : ""}
    ${pintarCampoQuiz(pregunta, valor)}
  `;

  // Las opciones avanzan solas al pulsarlas: en un cuestionario de seis
  // pasos, obligar a elegir Y ADEMÁS pulsar "Siguiente" duplica los
  // toques sin ganar nada.
  $("quiz-body").querySelectorAll("[data-opcion]").forEach((btn) => {
    btn.addEventListener("click", () => {
      quiz.respuestas[pregunta.id] = btn.dataset.opcion;
      if (quiz.paso < total - 1) { quiz.paso++; pintarQuiz(); }
      else pintarQuiz();
    });
  });

  const campo = $("quiz-input");
  if (campo) {
    campo.addEventListener("input", () => { quiz.respuestas[pregunta.id] = campo.value; });
    campo.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); avanzarQuiz(); } });
    setTimeout(() => campo.focus(), 30);
  }
}

function pintarCampoQuiz(pregunta, valor) {
  if (pregunta.tipo === "opciones") {
    return `<div class="quiz-options">
      ${pregunta.opciones.map((o) => `
        <button type="button" class="quiz-option ${valor === o.valor ? "is-on" : ""}" data-opcion="${esc(o.valor)}">
          <span class="quiz-option-icon" aria-hidden="true">${esc(o.icono ?? "")}</span>
          <span>${esc(o.etiqueta)}</span>
        </button>`).join("")}
    </div>`;
  }
  if (pregunta.tipo === "numero") {
    return `<div class="quiz-number">
      <input id="quiz-input" type="number" inputmode="decimal"
             min="${pregunta.min}" max="${pregunta.max}" step="${pregunta.paso}"
             value="${esc(String(valor))}" placeholder="—">
      <span>${esc(pregunta.unidad ?? "")}</span>
    </div>`;
  }
  return `<textarea id="quiz-input" class="quiz-text" rows="3"
            placeholder="Escribe lo que quieras, o déjalo en blanco">${esc(String(valor))}</textarea>`;
}

function avanzarQuiz() {
  const pregunta = nutri.PREGUNTAS[quiz.paso];
  const valor = quiz.respuestas[pregunta.id];

  if (!pregunta.opcional && (valor === undefined || valor === "")) {
    return mensajeQuiz("Contesta esto para seguir.");
  }
  if (pregunta.tipo === "numero") {
    const n = Number(valor);
    if (!Number.isFinite(n) || n < pregunta.min || n > pregunta.max) {
      return mensajeQuiz(`Tiene que estar entre ${pregunta.min} y ${pregunta.max} ${pregunta.unidad ?? ""}.`);
    }
    quiz.respuestas[pregunta.id] = n;
  }

  mensajeQuiz("");
  if (quiz.paso < nutri.PREGUNTAS.length - 1) { quiz.paso++; pintarQuiz(); }
  else calcularObjetivo();
}

const mensajeQuiz = (texto) => { $("quiz-status").textContent = texto; };

$("quiz-next").addEventListener("click", avanzarQuiz);
$("quiz-back").addEventListener("click", () => {
  if (quiz.paso > 0) { quiz.paso--; mensajeQuiz(""); pintarQuiz(); }
});

/** Le pide el objetivo a la IA, lo acota y lo guarda. */
async function calcularObjetivo() {
  const { valido, faltan } = nutri.validarRespuestas(quiz.respuestas);
  if (!valido) {
    // Se vuelve a la primera pregunta que falta en vez de dar un error
    // suelto: así se ve QUÉ hay que arreglar.
    quiz.paso = nutri.PREGUNTAS.findIndex((p) => p.id === faltan[0]);
    pintarQuiz();
    return mensajeQuiz("Falta contestar esto.");
  }

  $("quiz-next").disabled = true;
  mensajeQuiz("Calculando con la IA…");

  // La referencia de la fórmula se calcula SIEMPRE, antes de llamar: si
  // la IA falla, el objetivo sale igual y la sección no se queda
  // bloqueada por un error de red.
  const referencia = nutri.objetivoDeReferencia(quiz.respuestas);
  let propuesta = referencia;
  let explicacion = "Calculado con la fórmula de Mifflin-St Jeor a partir de tus datos.";
  let consejo = "";
  let avisos = [];
  let falloIA = null;

  try {
    const bruto = await ia.preguntarJSON(nutri.promptObjetivo(quiz.respuestas));
    const acotado = nutri.acotarObjetivo(bruto, quiz.respuestas);
    propuesta = acotado.objetivo;
    avisos = acotado.avisos;
    explicacion = String(bruto.explicacion ?? explicacion).slice(0, 600);
    consejo = String(bruto.consejo ?? "").slice(0, 300);
  } catch (error) {
    falloIA = error?.message ?? "La IA no ha contestado.";
  }

  await saveNutritionGoal({
    daily_calorie_goal: propuesta.calorias,
    protein_goal_grams: propuesta.proteina,
    carbs_goal_grams: propuesta.carbos,
    fat_goal_grams: propuesta.grasa,
    target_weight_kg: null,
    weekly_rate_kg: null,
  });

  guardarPerfil({ ...quiz.respuestas, explicacion, consejo, avisos, falloIA, calculado: nowISO() });

  quiz.forzado = false;
  $("quiz-next").disabled = false;
  mensajeQuiz("");
  await loadNutrition();
}

$("plan-redo").addEventListener("click", () => {
  empezarQuiz(perfilNutricion(), { forzado: true });
  loadNutrition();
});

// ── El plan ─────────────────────────────────────────────────────────

function pintarPlan(goal, perfil) {
  const numeros = [
    ["Calorías", Math.round(goal.daily_calorie_goal), "kcal"],
    ["Proteína", Math.round(goal.protein_goal_grams), "g"],
    ["Carbos", Math.round(goal.carbs_goal_grams), "g"],
    ["Grasas", Math.round(goal.fat_goal_grams), "g"],
  ];
  $("plan-numbers").innerHTML = numeros
    .map(([etiqueta, valor, unidad]) => `
      <div class="plan-number">
        <span class="plan-value">${valor}</span>
        <span class="plan-unit">${unidad}</span>
        <span class="plan-label">${etiqueta}</span>
      </div>`)
    .join("");

  // Si el cerrojo ha tenido que corregir a la IA, su explicación y su
  // consejo NO se enseñan. Dos razones, y las dos importan:
  //
  //   · La explicación describe un objetivo que ya no es el que hay. Una
  //     IA que proponía 900 kcal te cuenta por qué 900, mientras arriba
  //     pone 1718. Es la app contradiciéndose a sí misma.
  //   · El consejo sale del mismo modelo que acaba de proponerle una
  //     dieta de hambre a un adolescente, y va en verde y destacado, que
  //     es lo más visible de la tarjeta. "No comas después de las seis"
  //     no es un consejo que Habitium deba dar con su propia voz.
  //
  // Se sustituye por un texto propio que dice de dónde sale el número.
  const corregido = (perfil?.avisos?.length ?? 0) > 0 || perfil?.falloIA;

  $("plan-why").textContent = corregido
    ? "Este objetivo está calculado con la fórmula de Mifflin-St Jeor a partir de tus datos. Lo que proponía la IA no cuadraba, así que se ha ajustado — abajo tienes el detalle."
    : (perfil?.explicacion ?? "");

  $("plan-tip").textContent = corregido ? "" : (perfil?.consejo ?? "");
  $("plan-tip").hidden = corregido || !perfil?.consejo;

  // Los avisos del cerrojo se ENSEÑAN. Corregir el número de la IA a
  // escondidas sería peor que no corregirlo: la app estaría mintiendo
  // sobre de dónde sale su propio objetivo.
  const avisos = perfil?.avisos ?? [];
  const fallo = perfil?.falloIA;
  $("plan-warnings").innerHTML = [
    ...(fallo ? [`<li class="warn">La IA no contestó (${esc(fallo)}). Este objetivo sale de la fórmula.</li>`] : []),
    ...avisos.map((a) => `<li class="warn">${esc(a)}</li>`),
  ].join("");
}

// ── Foto ────────────────────────────────────────────────────────────

$("food-photo").addEventListener("change", async (e) => {
  const file = e.target.files?.[0];
  e.target.value = "";               // para poder repetir la misma foto
  if (!file) return;

  pintarResultadoIA(`<p class="ai-loading">📷 Mirando la foto…</p>`);
  try {
    const imagen = await ia.prepararFoto(file);
    const bruto = await ia.preguntarJSON(nutri.promptFoto(), { imagen });
    const comida = nutri.normalizarComida(bruto);

    const confianza = { alta: "", media: "La IA no lo tiene del todo claro.", baja: "La IA no está segura de qué es." };
    pintarResultadoIA(`
      <div class="ai-card">
        <h3>${esc(comida.nombre)}</h3>
        <div class="ai-macros">
          <span><b>${comida.calorias}</b> kcal</span>
          <span><b>${comida.proteina}</b> g P</span>
          <span><b>${comida.carbos}</b> g C</span>
          <span><b>${comida.grasa}</b> g G</span>
        </div>
        ${comida.nota ? `<p class="muted sm">${esc(comida.nota)}</p>` : ""}
        ${confianza[comida.confianza] ? `<p class="warn sm">${confianza[comida.confianza]} Revisa los números antes de guardarlos.</p>` : ""}
        <div class="composer-row">
          <select id="ai-meal" class="w-md">
            <option value="breakfast">Desayuno</option>
            <option value="lunch">Almuerzo</option>
            <option value="dinner">Cena</option>
            <option value="snack">Snack</option>
          </select>
          <button class="btn btn-primary" id="ai-save-food" type="button">Guardar</button>
          <button class="btn btn-ghost" id="ai-edit-food" type="button">Corregir a mano</button>
        </div>
      </div>`);

    // Se preselecciona la comida que toca por la hora: a las nueve de la
    // noche nadie está apuntando un desayuno.
    const momento = { desayuno: "breakfast", comida: "lunch", cena: "dinner" }[nutri.momentoDelDia()] ?? "snack";
    $("ai-meal").value = momento;

    $("ai-save-food").addEventListener("click", async () => {
      const entry = await store.insert("food_entries", {
        name: comida.nombre,
        date: nowISO(),
        meal_type: $("ai-meal").value,
        source: "ai",
        calories: comida.calorias,
        protein_grams: comida.proteina,
        carbs_grams: comida.carbos,
        fat_grams: comida.grasa,
        analyzed_by: ia.proveedor(),
      });
      pintarResultadoIA("");
      await awardXP("mealLogged", `meal:${idKey(entry.id)}`);
    });

    // "Corregir a mano" rellena el formulario de abajo en vez de guardar:
    // la IA acierta el plato y falla la ración más de lo que parece.
    $("ai-edit-food").addEventListener("click", () => {
      $("food-name").value = comida.nombre;
      $("food-calories").value = comida.calorias;
      $("food-protein").value = comida.proteina;
      $("food-carbs").value = comida.carbos;
      $("food-fat").value = comida.grasa;
      $("food-meal").value = $("ai-meal").value;
      pintarResultadoIA("");
      $("food-calories").focus();
    });
  } catch (error) {
    pintarResultadoIA(`<p class="warn">${esc(error?.message ?? "No se ha podido analizar la foto.")}</p>`);
  }
});

// ── "¿Qué como ahora?" ──────────────────────────────────────────────

$("food-suggest").addEventListener("click", async () => {
  const goal = await nutritionGoal();
  const perfil = perfilNutricion();
  if (!goal) return;

  const comidas = await todaysFood();
  const consumido = comidas.reduce(
    (s, e) => ({
      calorias: s.calorias + (e.calories ?? 0),
      proteina: s.proteina + (e.protein_grams ?? 0),
      carbos: s.carbos + (e.carbs_grams ?? 0),
      grasa: s.grasa + (e.fat_grams ?? 0),
    }),
    { calorias: 0, proteina: 0, carbos: 0, grasa: 0 }
  );

  pintarResultadoIA(`<p class="ai-loading">🍽️ Pensando qué te viene bien…</p>`);
  try {
    const sugerencia = await ia.preguntarJSON(
      nutri.promptRecomendacion({
        objetivo: {
          calorias: Math.round(goal.daily_calorie_goal),
          proteina: Math.round(goal.protein_goal_grams),
          carbos: Math.round(goal.carbs_goal_grams),
          grasa: Math.round(goal.fat_goal_grams),
        },
        consumido: {
          calorias: Math.round(consumido.calorias),
          proteina: Math.round(consumido.proteina),
          carbos: Math.round(consumido.carbos),
          grasa: Math.round(consumido.grasa),
        },
        momento: nutri.momentoDelDia(),
        respuestas: perfil,
        comidasDeHoy: comidas.map((c) => c.name),
      })
    );

    pintarResultadoIA(`
      <div class="ai-card">
        <h3>${esc(String(sugerencia.titulo ?? "").slice(0, 120))}</h3>
        <p>${esc(String(sugerencia.porque ?? "").slice(0, 400))}</p>
        ${Number(sugerencia.calorias) > 0 ? `
          <div class="ai-macros">
            <span><b>${Math.round(Number(sugerencia.calorias))}</b> kcal aprox.</span>
            ${Number(sugerencia.proteina) > 0 ? `<span><b>${Math.round(Number(sugerencia.proteina))}</b> g P</span>` : ""}
          </div>` : ""}
        ${sugerencia.alternativa ? `<p class="muted sm">O si no te apetece: ${esc(String(sugerencia.alternativa).slice(0, 200))}</p>` : ""}
      </div>`);
  } catch (error) {
    pintarResultadoIA(`<p class="warn">${esc(error?.message ?? "La IA no ha contestado.")}</p>`);
  }
});

function pintarResultadoIA(html) {
  const caja = $("ai-result");
  caja.innerHTML = html;
  caja.hidden = !html;
}

async function pintarComidasDelDia() {
  const entries = await todaysFood();
  $("food-total").textContent = `${Math.round(entries.reduce((s, e) => s + (e.calories ?? 0), 0))} kcal`;

  const pesos = (await store.all("weight_entries")).sort(byDateDesc);
  $("weight-last").textContent = pesos.length
    ? `último: ${pesos[0].weight_kg} kg · ${dayOf(pesos[0].date)}`
    : "";

  const list = $("food-list");
  if (!entries.length) {
    list.innerHTML = emptyState("🍽️", "Nada registrado hoy", "Escribe arriba qué has comido y sus calorías.");
    return;
  }

  list.innerHTML = entries
    .map(
      (e) => `
      <li class="row">
        <div class="row-icon">${MEALS[e.meal_type]?.icon ?? "🍽️"}</div>
        <div class="row-main">
          <div class="row-title">${esc(e.name)}</div>
          <div class="row-sub">
            <span>${MEALS[e.meal_type]?.name ?? ""} · ${timeOf(e.date)}</span>
            <span>P ${Math.round(e.protein_grams)} · C ${Math.round(e.carbs_grams)} · G ${Math.round(e.fat_grams)} g</span>
          </div>
        </div>
        <div class="row-value">${Math.round(e.calories)} kcal</div>
        <button class="delete" data-del="${e.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
    )
    .join("");

  wireDelete(list, "food_entries");
}

$("food-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const entry = await store.insert("food_entries", {
    name: $("food-name").value.trim(),
    date: nowISO(),
    meal_type: $("food-meal").value,
    source: "manual",
    calories: Number($("food-calories").value) || 0,
    protein_grams: Number($("food-protein").value) || 0,
    carbs_grams: Number($("food-carbs").value) || 0,
    fat_grams: Number($("food-fat").value) || 0,
  });
  e.target.reset();
  // La clave lleva el id de la comida y NO la fecha, igual que en iOS
  // (NutritionRepository): cada comida se premia una vez en su vida.
  await awardXP("mealLogged", `meal:${idKey(entry.id)}`);
});

// ── Agenda ──────────────────────────────────────────────────────────

async function loadPlanner() {
  await pintarCalendario();

  const tasks = (await store.all("planner_tasks")).sort((a, b) => {
    if (!a.due_date) return 1;
    if (!b.due_date) return -1;
    return new Date(a.due_date) - new Date(b.due_date);
  });

  const pending = tasks.filter((t) => !t.is_completed);
  $("task-count").textContent = String(pending.length);
  renderTasks($("task-list"), pending, "No tienes tareas pendientes. 🎉");
  renderTasks($("task-done-list"), tasks.filter((t) => t.is_completed), "Nada completado todavía", "✅", "Lo que vayas marcando aparecerá aquí.");
}

function renderTasks(list, tasks, emptyText, emptyIcon = "📋", emptyHint = "") {
  if (!tasks.length) {
    list.innerHTML = emptyState(emptyIcon, emptyText, emptyHint);
    return;
  }

  const today = startOfToday().getTime();
  list.innerHTML = tasks
    .map((t) => {
      const overdue =
        !t.is_completed && t.due_date && new Date(t.due_date).setHours(0, 0, 0, 0) < today;
      return `
      <li class="row">
        <button class="check ${t.is_completed ? "is-checked" : ""}"
                data-toggle="${t.id}" data-done="${t.is_completed}"
                aria-label="Marcar como completada">✓</button>
        <div class="row-main">
          <div class="row-title ${t.is_completed ? "is-done" : ""}">${esc(t.title)}</div>
          ${t.due_date ? `<div class="row-sub"><span>${overdue ? "⚠️ " : ""}${dayOf(t.due_date)}</span></div>` : ""}
        </div>
        <button class="delete" data-del="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-toggle]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const completing = btn.dataset.done !== "true";
      const task = await store.update("planner_tasks", btn.dataset.toggle, {
        is_completed: completing,
      });
      // Solo se premia completar, nunca desmarcar. La clave lleva el id
      // de la tarea y no la fecha: una tarea concreta se premia una vez
      // en su vida, aunque se marque y desmarque en días distintos.
      if (completing && task) {
        await awardXP(
          task.is_focus ? "focusTaskCompleted" : "taskCompleted",
          `task:${idKey(task.id)}`
        );
      }
    });
  });

  wireDelete(list, "planner_tasks");
}

$("task-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const due = $("task-due").value;
  await store.insert("planner_tasks", {
    title: $("task-title").value.trim(),
    // El input date da "YYYY-MM-DD" sin hora; mediodía evita que un
    // desfase de zona horaria lo mueva al día anterior.
    due_date: due ? new Date(`${due}T12:00:00`).toISOString() : null,
    is_completed: false,
    priority: "medium",
    is_focus: false,
  });
  e.target.reset();
});

// ── Finanzas ────────────────────────────────────────────────────────

/** Una sola lista de categorías en toda la app: la de finanzas-ia.js.
 *  Antes había dos —esta y aquella— y ya se habían separado: la web
 *  clasificaba gastos como "shopping" y ni este objeto ni el enum de
 *  Swift lo conocían, así que el mismo gasto se veía distinto según el
 *  dispositivo. */
const CATEGORIES = Object.fromEntries(
  Object.entries(fin.CATEGORIAS).map(([id, c]) => [id, { name: c.nombre, icon: c.icono }])
);

const monthTransactions = async () =>
  (await store.all("transactions"))
    .filter((t) => inRange(t.date, startOfMonth(), startOfNextMonth()))
    .sort(byDateDesc);

async function budgetSettings() {
  const b = await store.getSingleton("budget_settings");
  if (b?.currency_code) currencyCode = b.currency_code;
  return b;
}

// ── Finanzas: plan de ahorro con las cuentas hechas ─────────────────
//
// Mismo patrón que Nutrición, y por la misma razón: al entrar por
// primera vez se pregunta lo que hace falta, y a partir de ahí hay un
// plan en vez de un número puesto a ojo.
//
// La diferencia con Nutrición es quién manda. Allí la IA propone y la
// fórmula acota; aquí la ARITMÉTICA calcula y la IA solo comenta. Un
// plan de ahorro es restar y dividir: no hay nada que opinar sobre si
// 500 € al mes caben en 20 € de margen.

const CLAVE_FIN = "habitium.finanzas.perfil";

function perfilFinanzas() {
  try { return JSON.parse(localStorage.getItem(CLAVE_FIN) ?? "null"); } catch (e) { return null; }
}
function guardarPerfilFinanzas(datos) {
  try { localStorage.setItem(CLAVE_FIN, JSON.stringify(datos)); } catch (e) {}
}

let fquiz = { paso: 0, respuestas: {}, forzado: false, cargado: false };
let generacionFinanzas = 0;

async function loadFinance() {
  const generacion = ++generacionFinanzas;
  const budget = await budgetSettings();   // fija la moneda antes de formatear
  const perfil = perfilFinanzas();
  const txs = await store.all("transactions");
  if (generacion !== generacionFinanzas) return;   // ver loadNutrition

  // El cuestionario se DEDUCE, no se guarda en una bandera: un pintado
  // tardío no puede reabrirlo después de haberlo terminado.
  const faltaPerfil = !perfil;
  const tocaQuiz = fquiz.forzado || faltaPerfil;

  $("finance-quiz").hidden = !tocaQuiz;
  $("finance-plan").hidden = tocaQuiz;

  // Con el cuestionario abierto se esconde TODO lo demás. Dejarlo a la
  // vista enseña tres tarjetas con guiones y dos titulillos sin nada
  // debajo, que es lo que se veía en la captura: parece que la app está
  // rota en vez de que te está preguntando algo.
  for (const el of document.querySelectorAll("#view-finance > *")) {
    if (el.id === "finance-quiz" || el.id === "finance-plan") continue;
    el.hidden = tocaQuiz;
  }

  if (tocaQuiz) {
    if (!fquiz.cargado) empezarFQuiz(perfil);
    pintarFQuiz();
    return;
  }

  pintarPlanAhorro(perfil, txs);
  pintarResumenMes(budget, txs);
  pintarCategorias(txs);
  await pintarMovimientos();
}

// ── El cuestionario ─────────────────────────────────────────────────

function empezarFQuiz(previo, { forzado = false } = {}) {
  fquiz = { paso: 0, respuestas: { ...(previo ?? {}) }, forzado, cargado: true };
}

function pintarFQuiz() {
  const pregunta = fin.PREGUNTAS[fquiz.paso];
  if (!pregunta) return;

  const total = fin.PREGUNTAS.length;
  $("fq-bar").style.width = `${Math.round((fquiz.paso / total) * 100)}%`;
  $("fq-count").textContent = `${fquiz.paso + 1} de ${total}`;
  $("fq-back").disabled = fquiz.paso === 0;
  $("fq-next").textContent = fquiz.paso === total - 1 ? "Ver mi plan" : "Siguiente";

  const valor = fquiz.respuestas[pregunta.id] ?? "";
  $("fq-body").innerHTML = `
    <h2 class="quiz-question">${esc(pregunta.texto)}</h2>
    ${pregunta.ayuda ? `<p class="muted sm">${esc(pregunta.ayuda)}</p>` : ""}
    ${campoFQuiz(pregunta, valor)}
  `;

  $("fq-body").querySelectorAll("[data-fopcion]").forEach((btn) => {
    btn.addEventListener("click", () => {
      fquiz.respuestas[pregunta.id] = btn.dataset.fopcion;
      if (fquiz.paso < total - 1) fquiz.paso++;
      pintarFQuiz();
    });
  });

  const campo = $("fq-input");
  if (campo) {
    campo.addEventListener("input", () => { fquiz.respuestas[pregunta.id] = campo.value; });
    campo.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); avanzarFQuiz(); } });
    setTimeout(() => campo.focus(), 30);
  }
}

function campoFQuiz(pregunta, valor) {
  if (pregunta.tipo === "opciones") {
    return `<div class="quiz-options">
      ${pregunta.opciones.map((o) => `
        <button type="button" class="quiz-option ${valor === o.valor ? "is-on" : ""}" data-fopcion="${esc(o.valor)}">
          <span class="quiz-option-icon" aria-hidden="true">${esc(o.icono ?? "")}</span>
          <span>${esc(o.etiqueta)}</span>
        </button>`).join("")}
    </div>`;
  }
  if (pregunta.tipo === "dinero" || pregunta.tipo === "numero") {
    // El símbolo va DELANTE del número en el caso del dinero y detrás en
    // "meses". Suena a detalle tonto, pero "12 €" y "€ 12" se leen
    // distinto, y en España el euro va detrás.
    const unidad = pregunta.tipo === "dinero" ? "€" : (pregunta.unidad ?? "");
    return `<div class="quiz-number">
      <input id="fq-input" type="number" inputmode="decimal"
             min="${pregunta.min}" max="${pregunta.max}" step="${pregunta.tipo === "dinero" ? "0.01" : (pregunta.paso ?? 1)}"
             value="${esc(String(valor))}" placeholder="—">
      <span>${esc(unidad)}</span>
    </div>`;
  }
  return `<textarea id="fq-input" class="quiz-text" rows="3"
            placeholder="Escribe lo que quieras, o déjalo en blanco">${esc(String(valor))}</textarea>`;
}

function avanzarFQuiz() {
  const pregunta = fin.PREGUNTAS[fquiz.paso];
  const valor = fquiz.respuestas[pregunta.id];

  if (!pregunta.opcional && (valor === undefined || valor === "")) {
    return mensajeFQuiz("Contesta esto para seguir.");
  }
  if (pregunta.tipo === "dinero" || pregunta.tipo === "numero") {
    const n = Number(valor);
    if (!Number.isFinite(n) || n < pregunta.min || n > pregunta.max) {
      const unidad = pregunta.tipo === "dinero" ? "€" : (pregunta.unidad ?? "");
      return mensajeFQuiz(`Tiene que estar entre ${pregunta.min} y ${pregunta.max} ${unidad}.`);
    }
    fquiz.respuestas[pregunta.id] = n;
  }

  mensajeFQuiz("");
  if (fquiz.paso < fin.PREGUNTAS.length - 1) { fquiz.paso++; pintarFQuiz(); }
  else montarPlanAhorro();
}

const mensajeFQuiz = (texto) => { $("fq-status").textContent = texto; };

$("fq-next").addEventListener("click", avanzarFQuiz);
$("fq-back").addEventListener("click", () => {
  if (fquiz.paso > 0) { fquiz.paso--; mensajeFQuiz(""); pintarFQuiz(); }
});

/** Monta el plan. Las cuentas se hacen SIEMPRE; la IA solo comenta, y
 *  si no contesta el plan sale igual. */
async function montarPlanAhorro() {
  const { valido, faltan } = fin.validarRespuestas(fquiz.respuestas);
  if (!valido) {
    fquiz.paso = fin.PREGUNTAS.findIndex((p) => p.id === faltan[0]);
    pintarFQuiz();
    return mensajeFQuiz("Falta contestar esto.");
  }

  const plan = fin.calcularPlan(fquiz.respuestas);
  const avisos = fin.avisosDelPlan(plan, fquiz.respuestas);

  // El presupuesto y el objetivo SÍ se sincronizan: son datos de la app.
  // Lo que no sube a la nube es el cuestionario (cuánto ganas, cuánto
  // gastas), igual que en Nutrición.
  await store.putSingleton("budget_settings", {
    monthly_budget: plan.presupuesto,
    total_savings: plan.ahorroActual,
    currency_code: (await budgetSettings())?.currency_code ?? "EUR",
    savings_goal_amount: plan.objetivo,
    savings_goal_date: new Date(Date.now() + plan.meses * 30 * 86400000).toISOString(),
  });

  let resumen = "";
  let consejo = "";
  let falloIA = null;

  if (ia.hayClave()) {
    $("fq-next").disabled = true;
    mensajeFQuiz("Preguntando a la IA…");
    try {
      const txs = await store.all("transactions");
      const bruto = await ia.preguntarJSON(
        fin.promptPlan(fquiz.respuestas, plan, fin.porCategoria(txs))
      );
      resumen = String(bruto.resumen ?? "").slice(0, 600);
      consejo = String(bruto.consejo ?? "").slice(0, 300);
      if (bruto.recorte) consejo += ` ${String(bruto.recorte).slice(0, 200)}`;
    } catch (error) {
      falloIA = error?.message ?? "La IA no ha contestado.";
    }
    $("fq-next").disabled = false;
  }

  guardarPerfilFinanzas({ ...fquiz.respuestas, plan, avisos, resumen, consejo, falloIA, calculado: nowISO() });
  fquiz.forzado = false;
  mensajeFQuiz("");
  await loadFinance();
}

$("fplan-redo").addEventListener("click", () => {
  empezarFQuiz(perfilFinanzas(), { forzado: true });
  loadFinance();
});

// ── El plan pintado ─────────────────────────────────────────────────

function pintarPlanAhorro(perfil, txs) {
  const plan = perfil?.plan ?? fin.calcularPlan(perfil ?? {});
  const pct = plan.objetivo > 0 ? Math.min(100, Math.round((plan.ahorroActual / plan.objetivo) * 100)) : 0;

  $("fplan-now").textContent = money(plan.ahorroActual);
  $("fplan-target").textContent = `de ${money(plan.objetivo)} · ${pct}%`;
  $("fplan-bar").style.width = `${pct}%`;
  $("fplan-bar").classList.toggle("is-stuck", !plan.viable);

  // Si las cuentas no dan, el texto de la IA NO se enseña — igual que en
  // Nutrición cuando el cerrojo corrige. Un "vas muy bien" encima de un
  // plan que no sale es peor que no decir nada.
  const cuadra = plan.viable && !perfil?.falloIA;

  $("fplan-why").textContent = cuadra
    ? (perfil?.resumen || `Apartando ${money(plan.porMes)} al mes llegas a ${money(plan.objetivo)} en ${plan.meses} ${plan.meses === 1 ? "mes" : "meses"}.`)
    : `Con tus números, apartar ${money(plan.necesarioPorMes)} al mes es lo que haría falta. Abajo tienes por qué no sale y qué cambiar.`;

  $("fplan-tip").textContent = cuadra ? (perfil?.consejo ?? "") : "";
  $("fplan-tip").hidden = !cuadra || !perfil?.consejo;

  const avisos = perfil?.avisos ?? [];
  $("fplan-warnings").innerHTML = [
    ...avisos.map((a) => `<li class="warn">${esc(a)}</li>`),
    ...(perfil?.falloIA ? [`<li class="warn">La IA no contestó (${esc(perfil.falloIA)}). Las cuentas son las mismas: no dependen de ella.</li>`] : []),
  ].join("");
}

function pintarResumenMes(budget, txs) {
  const estado = fin.estadoDelMes(txs, budget?.monthly_budget ?? 0);

  $("fin-income").textContent = money(estado.ingresado);
  $("fin-expense").textContent = money(estado.gastado);
  $("fin-available").textContent = money(Math.max(0, estado.disponible));

  // El aviso por proyección: "a este ritmo acabas el mes en X". Decirlo
  // el día 28 no sirve de nada; decirlo el día 10 sí.
  const caja = $("fin-available").closest(".card");
  caja?.classList.toggle("is-warning", estado.teVasAPasar);
  if (estado.porDia !== null) {
    $("fin-available").title = `Te quedan ${money(estado.porDia)} al día hasta fin de mes`;
  }
}

function pintarCategorias(txs) {
  const cats = fin.porCategoria(txs);
  const total = cats.reduce((s, c) => s + c.importe, 0);
  $("fin-month-total").textContent = money(total);

  if (!cats.length) {
    $("fin-categories").innerHTML = emptyState("💶", "Nada gastado este mes", "Apunta un gasto y aparecerá aquí, repartido por categorías.");
    return;
  }

  const max = cats[0].importe;
  $("fin-categories").innerHTML = cats
    .map((c) => `
      <div class="cat-row">
        <div class="cat-name">${esc(c.icono)} ${esc(c.nombre)}</div>
        <div class="cat-track"><i style="width:${max > 0 ? Math.round((c.importe / max) * 100) : 0}%"></i></div>
        <div class="cat-value">${money(c.importe)} <small>${c.porcentaje}%</small></div>
      </div>`)
    .join("");
}

// ── Gasto rápido: "4,20 bocadillo" ──────────────────────────────────
//
// Es el mismo camino que usa el atajo de Apple Pay (ver el README). Por
// eso funciona SIN IA: en la cola del súper con mala cobertura, si
// dependiera de que la IA conteste fallaría justo cuando hace falta. La
// IA solo afina la categoría, y si no está, se usa la tabla de palabras.

$("quick-expense").addEventListener("submit", async (e) => {
  e.preventDefault();
  const texto = $("quick-text").value.trim();
  if (!texto) return;

  const local = fin.interpretarGasto(texto);
  if (!local) {
    $("quick-status").textContent = "No encuentro el importe. Escribe algo como «4,20 bocadillo».";
    return;
  }

  $("quick-text").value = "";
  $("quick-status").textContent = "";

  // Se guarda YA con lo que se ha entendido en local. Si la IA mejora la
  // categoría después, se actualiza la fila. Al revés —esperar a la IA
  // para guardar— sería perder el gasto cuando no hay red.
  const tx = await store.insert("transactions", {
    amount: local.importe,
    type: "expense",
    category: local.categoria,
    note: local.nota,
    date: nowISO(),
  });

  if (ia.hayClave()) {
    try {
      const mejor = fin.normalizarGasto(await ia.preguntarJSON(fin.promptClasificar(texto)));
      if (mejor.importe && mejor.categoria !== local.categoria) {
        await store.update("transactions", tx.id, { category: mejor.categoria });
      }
    } catch (error) {
      /* la IA es un extra: el gasto ya está apuntado */
    }
  }
});

// ── Agenda: el calendario del mes ───────────────────────────────────
//
// Un calendario que solo enseña los días es un adorno. Este enseña un
// punto por cada cosa que tienes ese día —tarea, evento, examen— y al
// pulsar un día filtra la lista de abajo. Eso es lo que lo convierte en
// la forma de mirar el mes en vez de un cuadro bonito.

let mesCalendario = null;   // null = el mes de hoy
let diaElegido = null;

const claveFecha = (f) =>
  `${f.getFullYear()}-${String(f.getMonth() + 1).padStart(2, "0")}-${String(f.getDate()).padStart(2, "0")}`;

async function cosasDelMes() {
  const [tasks, events, examenes] = await Promise.all([
    store.all("planner_tasks"),
    store.all("planner_events"),
    store.all("study_events"),
  ]);

  const mapa = new Map();
  const mete = (fecha, tipo, titulo, id) => {
    if (!fecha) return;
    const d = new Date(fecha);
    if (Number.isNaN(d.getTime())) return;
    const k = claveFecha(d);
    if (!mapa.has(k)) mapa.set(k, []);
    mapa.get(k).push({ tipo, titulo, id, fecha: d });
  };

  for (const t of tasks) if (!t.is_completed) mete(t.due_date, "task", t.title, t.id);
  for (const e of events) mete(e.start_date, "event", e.title, e.id);
  for (const x of examenes) mete(x.date, "exam", x.title, x.id);

  for (const lista of mapa.values()) lista.sort((a, b) => a.fecha - b.fecha);
  return mapa;
}

async function pintarCalendario() {
  const hoy = new Date();
  const base = mesCalendario ?? new Date(hoy.getFullYear(), hoy.getMonth(), 1);
  const cosas = await cosasDelMes();

  const titulo = base.toLocaleDateString("es-ES", { month: "long", year: "numeric" });
  $("cal-title").textContent = titulo.charAt(0).toUpperCase() + titulo.slice(1);

  // El primer día de la rejilla es el lunes de la semana del día 1.
  // getDay() devuelve domingo=0, de ahí el +6 %7: es la fuente de la
  // mitad de los calendarios que empiezan torcidos.
  const primero = new Date(base.getFullYear(), base.getMonth(), 1);
  const desplazamiento = (primero.getDay() + 6) % 7;
  const inicio = new Date(primero);
  inicio.setDate(1 - desplazamiento);

  const celdas = [];
  for (let i = 0; i < 42; i++) {
    const dia = new Date(inicio);
    dia.setDate(inicio.getDate() + i);

    const deEsteMes = dia.getMonth() === base.getMonth();
    const esHoy = claveFecha(dia) === claveFecha(hoy);
    const k = claveFecha(dia);
    const suyo = cosas.get(k) ?? [];
    const tipos = [...new Set(suyo.map((c) => c.tipo))];

    celdas.push(`
      <button type="button" class="cal-day ${deEsteMes ? "" : "is-out"} ${esHoy ? "is-today" : ""} ${diaElegido === k ? "is-picked" : ""}"
              data-dia="${k}" role="gridcell"
              aria-label="${dia.getDate()} de ${titulo}${suyo.length ? `, ${suyo.length} cosas` : ""}">
        <span class="cal-num">${dia.getDate()}</span>
        <span class="cal-dots">${tipos.map((t) => `<i class="dot ${t}"></i>`).join("")}</span>
      </button>`);

    // Seis semanas siempre daría filas vacías en muchos meses. Se corta
    // en cuanto se ha pasado el mes y se ha cerrado la semana.
    if (i >= 27 && (i + 1) % 7 === 0 && dia.getMonth() !== base.getMonth()) break;
  }

  $("cal-grid").innerHTML = celdas.join("");
  $("cal-grid").querySelectorAll("[data-dia]").forEach((btn) => {
    btn.addEventListener("click", () => {
      diaElegido = diaElegido === btn.dataset.dia ? null : btn.dataset.dia;
      pintarCalendario();
      pintarDiaElegido(cosas);
    });
  });

  pintarDiaElegido(cosas);
}

function pintarDiaElegido(cosas) {
  const caja = $("cal-day");
  if (!diaElegido) { caja.hidden = true; return; }

  const [a, m, d] = diaElegido.split("-").map(Number);
  const fecha = new Date(a, m - 1, d);
  const texto = fecha.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" });
  $("cal-day-title").textContent = texto.charAt(0).toUpperCase() + texto.slice(1);

  const suyo = cosas.get(diaElegido) ?? [];
  const ETIQUETAS = { task: ["✅", "Tarea"], event: ["📅", "Evento"], exam: ["🎓", "Examen"] };

  $("cal-day-list").innerHTML = suyo.length
    ? suyo.map((c) => `
        <li class="row">
          <div class="row-icon">${ETIQUETAS[c.tipo]?.[0] ?? "•"}</div>
          <div class="row-main">
            <div class="row-title">${esc(c.titulo)}</div>
            <div class="row-sub"><span>${ETIQUETAS[c.tipo]?.[1] ?? ""} · ${timeOf(c.fecha.toISOString())}</span></div>
          </div>
        </li>`).join("")
    : emptyState("🎉", "Nada este día", "Tienes el día libre.");

  caja.hidden = false;
}

$("cal-prev").addEventListener("click", () => {
  const base = mesCalendario ?? new Date();
  mesCalendario = new Date(base.getFullYear(), base.getMonth() - 1, 1);
  diaElegido = null;
  pintarCalendario();
});
$("cal-next").addEventListener("click", () => {
  const base = mesCalendario ?? new Date();
  mesCalendario = new Date(base.getFullYear(), base.getMonth() + 1, 1);
  diaElegido = null;
  pintarCalendario();
});
$("cal-today").addEventListener("click", () => {
  mesCalendario = null;
  diaElegido = claveFecha(new Date());
  pintarCalendario();
});
$("cal-day-close").addEventListener("click", () => {
  diaElegido = null;
  pintarCalendario();
});

/** Solo la lista de movimientos. Los totales y las categorías los
 *  pintan ahora pintarResumenMes y pintarCategorias, que usan las
 *  cuentas de finanzas-ia.js — dejarlo aquí también los pintaría dos
 *  veces con dos lógicas distintas. */
async function pintarMovimientos() {
  await budgetSettings();      // fija la moneda antes de formatear
  const txs = await monthTransactions();

  const list = $("tx-list");
  if (!txs.length) {
    list.innerHTML = emptyState("💶", "Sin movimientos este mes", "Apunta un gasto o un ingreso con el formulario de arriba.");
    return;
  }

  list.innerHTML = txs
    .map((t) => {
      const isIncome = t.type === "income";
      return `
      <li class="row">
        <div class="row-icon">${CATEGORIES[t.category]?.icon ?? "•"}</div>
        <div class="row-main">
          <div class="row-title">${esc(t.note || CATEGORIES[t.category]?.name || "Movimiento")}</div>
          <div class="row-sub"><span>${CATEGORIES[t.category]?.name ?? ""} · ${dayOf(t.date)}</span></div>
        </div>
        <div class="row-value ${isIncome ? "is-income" : "is-expense"}">${isIncome ? "+" : "−"}${money(t.amount)}</div>
        <button class="delete" data-del="${t.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  wireDelete(list, "transactions");
}

$("tx-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  await store.insert("transactions", {
    amount: Number($("tx-amount").value) || 0,
    type: $("tx-type").value,
    category: $("tx-category").value,
    note: $("tx-note").value.trim() || null,
    date: nowISO(),
  });
  e.target.reset();
});

// ── Hábitos ─────────────────────────────────────────────────────────

// Mismas plantillas que HabitTemplate.swift en iOS.
const HABIT_TEMPLATES = [
  { name: "Tiempo de pantalla", kind: "numeric", target: 3, dir: "atMost", unit: "h" },
  { name: "Agua", kind: "numeric", target: 8, dir: "atLeast", unit: "vasos" },
  { name: "Dormir", kind: "numeric", target: 8, dir: "atLeast", unit: "h" },
  { name: "Ejercicio", kind: "checkbox" },
  { name: "Leer", kind: "checkbox" },
  { name: "Meditar", kind: "checkbox" },
];

function syncHabitKindFields() {
  const numeric = $("habit-kind").value === "numeric";
  $("habit-target").hidden = !numeric;
  $("habit-direction").hidden = !numeric;
  $("habit-unit").hidden = !numeric;
}
$("habit-kind").addEventListener("change", syncHabitKindFields);

$("habit-templates").innerHTML = HABIT_TEMPLATES.map(
  (t, i) => `<button class="chip" type="button" data-tpl="${i}">${esc(t.name)}</button>`
).join("");

$("habit-templates").querySelectorAll("[data-tpl]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const t = HABIT_TEMPLATES[Number(btn.dataset.tpl)];
    $("habit-name").value = t.name;
    $("habit-kind").value = t.kind;
    syncHabitKindFields();
    $("habit-target").value = t.target ?? "";
    $("habit-direction").value = t.dir ?? "atLeast";
    $("habit-unit").value = t.unit ?? "";
  });
});

/** ¿Cumple este registro el objetivo? Misma regla que
 *  HabitStatus.isGoalMetToday en iOS. */
function goalMet(habit, log) {
  if (!log) return false;
  if (habit.kind === "checkbox") return log.is_completed;
  if (log.value == null || habit.target_value == null) return false;
  return habit.goal_direction === "atMost"
    ? log.value <= habit.target_value
    : log.value >= habit.target_value;
}

/** Días consecutivos cumpliendo el objetivo, hacia atrás desde hoy —
 *  mismo recorrido que HabitRepository.streak(for:) en iOS. */
function streakFor(habit, logs) {
  const byDay = new Map();
  for (const log of logs) {
    const d = new Date(log.date);
    d.setHours(0, 0, 0, 0);
    byDay.set(d.getTime(), log);
  }

  const cursor = startOfToday();
  // Si hoy aún no está cumplido, la racha se mide desde ayer — no se
  // rompe solo porque el día no haya terminado todavía.
  if (!goalMet(habit, byDay.get(cursor.getTime()))) cursor.setDate(cursor.getDate() - 1);

  let streak = 0;
  while (goalMet(habit, byDay.get(cursor.getTime()))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

const logForToday = (logs, habitId) =>
  logs.find((l) => l.habit_id === habitId && sameDay(l.date, startOfToday()));

async function fetchHabits() {
  const habits = (await store.all("habits"))
    .filter((h) => h.is_active)
    .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
  return { habits, logs: await store.all("habit_logs") };
}

async function loadHabits() {
  const { habits, logs } = await fetchHabits();
  const list = $("habit-list");

  if (!habits.length) {
    list.innerHTML = emptyState("🔁", "Aún no tienes hábitos", "Toca una plantilla de arriba: en dos segundos tienes el primero.");
    return;
  }

  list.innerHTML = habits
    .map((h) => {
      const log = logForToday(logs, h.id);
      const streak = streakFor(h, logs.filter((l) => l.habit_id === h.id));
      const met = goalMet(h, log);

      const control =
        h.kind === "checkbox"
          ? `<button class="check ${log?.is_completed ? "is-checked" : ""}"
                     data-toggle-habit="${h.id}" data-done="${!!log?.is_completed}"
                     aria-label="Marcar como hecho">✓</button>`
          : `<input class="numeric-input" type="number" step="0.1" min="0"
                    value="${log?.value ?? ""}" data-log-habit="${h.id}"
                    placeholder="${esc(h.unit ?? "")}" aria-label="Valor de hoy">`;

      const target =
        h.kind === "numeric" && h.target_value != null
          ? `${h.goal_direction === "atMost" ? "máx." : "mín."} ${h.target_value}${h.unit ? " " + esc(h.unit) : ""}`
          : "";

      return `
      <li class="row">
        <div class="row-icon">${met ? "✅" : "⚪️"}</div>
        <div class="row-main">
          <div class="row-title">${esc(h.name)}</div>
          <div class="row-sub">
            ${target ? `<span>${target}</span>` : ""}
            ${streak > 0 ? `<span class="streak">🔥 ${streak} días</span>` : ""}
          </div>
        </div>
        ${control}
        <button class="delete" data-del="${h.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`;
    })
    .join("");

  list.querySelectorAll("[data-toggle-habit]").forEach((btn) => {
    btn.addEventListener("click", () =>
      upsertHabitLog(btn.dataset.toggleHabit, { is_completed: btn.dataset.done !== "true" })
    );
  });

  list.querySelectorAll("[data-log-habit]").forEach((input) => {
    input.addEventListener("change", () => {
      const value = input.value === "" ? null : Number(input.value);
      // Un número registrado cuenta como "hecho" ese día, se cumpla el
      // objetivo o no — igual que HabitRepository.logValue en iOS.
      upsertHabitLog(input.dataset.logHabit, { value, is_completed: value != null });
    });
  });

  wireDelete(list, "habits");
}

/** Crea o actualiza el registro de HOY para un hábito. */
async function upsertHabitLog(habitId, fields) {
  const existing = logForToday(await store.all("habit_logs"), habitId);
  const log = existing
    ? await store.update("habit_logs", existing.id, fields)
    : await store.insert("habit_logs", {
        habit_id: habitId,
        date: startOfToday().toISOString(),
        is_completed: false,
        ...fields,
      });

  await awardHabitXP(habitId);
  return log;
}

/** Experiencia por cumplir un hábito y, si con este se cierra el día
 *  entero, la bonificación de "todos los hábitos".
 *
 *  Se comprueba el objetivo de verdad (goalMet) y no el simple
 *  `is_completed`: en un hábito numérico —"bebe 2 litros"— apuntar medio
 *  litro deja el registro creado pero el objetivo sin cumplir, y premiar
 *  eso sería premiar el gesto y no el hábito. */
async function awardHabitXP(habitId) {
  const { habits, logs } = await fetchHabits();
  const habit = habits.find((h) => h.id === habitId);
  if (!habit || !goalMet(habit, logForToday(logs, habitId))) return;

  await awardXP("habitCompleted", prog.dedupeKey(`habit:${idKey(habitId)}`));

  if (habits.length && habits.every((h) => goalMet(h, logForToday(logs, h.id)))) {
    await awardXP("allHabitsCompleted", prog.dedupeKey("all-habits"));
  }
}

$("habit-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const numeric = $("habit-kind").value === "numeric";
  await store.insert("habits", {
    name: $("habit-name").value.trim(),
    symbol_name: "checkmark.circle.fill",
    kind: $("habit-kind").value,
    target_value: numeric ? Number($("habit-target").value) || null : null,
    goal_direction: numeric ? $("habit-direction").value : "atLeast",
    unit: numeric ? $("habit-unit").value.trim() || null : null,
    is_active: true,
    sort_order: 0,
    linked_to_workouts: false,
  });
  e.target.reset();
  syncHabitKindFields();
});

// ── Medicación ──────────────────────────────────────────────────────

/** Cruza los horarios de cada medicamento con los registros de hoy —
 *  misma construcción que MedicationRepository.todaysDoses() en iOS. */
async function todaysDoses() {
  const meds = (await store.all("medications"))
    .filter((m) => m.is_active)
    .sort((a, b) => a.name.localeCompare(b.name));

  const logs = (await store.all("medication_dose_logs")).filter((l) =>
    sameDay(l.date, startOfToday())
  );

  const doses = [];
  for (const med of meds) {
    for (const minute of med.reminder_minutes_since_midnight ?? []) {
      const log = logs.find((l) => l.medication_id === med.id && l.minute_of_day === minute);
      doses.push({
        med,
        minute,
        taken: !!log?.taken_at,
        skipped: !!log?.skipped,
        logId: log?.id ?? null,
      });
    }
  }
  return { meds, doses: doses.sort((a, b) => a.minute - b.minute) };
}

async function loadMedication() {
  const { meds, doses } = await todaysDoses();

  const list = $("dose-list");
  list.innerHTML = doses.length
    ? doses
        .map(
          (d, i) => `
      <li class="row">
        <button class="check ${d.taken ? "is-checked" : ""}"
                data-dose="${i}" aria-label="Marcar como tomada">✓</button>
        <div class="row-icon">💊</div>
        <div class="row-main">
          <div class="row-title ${d.taken ? "is-done" : ""}">${esc(d.med.name)}</div>
          <div class="row-sub">
            <span>${minutesToTime(d.minute)}</span>
            ${d.med.dosage ? `<span>${esc(d.med.dosage)}</span>` : ""}
            ${d.skipped ? `<span>omitida</span>` : ""}
          </div>
        </div>
      </li>`
        )
        .join("")
    : emptyState("💊", "Ninguna toma para hoy", "Si tomas algo a diario, añádelo abajo y te lo recordamos.");

  list.querySelectorAll("[data-dose]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const d = doses[Number(btn.dataset.dose)];
      setDoseTaken(d, !d.taken);
    });
  });

  const medList = $("med-list");
  medList.innerHTML = meds.length
    ? meds
        .map(
          (m) => `
      <li class="row">
        <div class="row-icon">💊</div>
        <div class="row-main">
          <div class="row-title">${esc(m.name)}</div>
          <div class="row-sub">
            <span>${(m.reminder_minutes_since_midnight ?? []).map(minutesToTime).join(" · ") || "sin horarios"}</span>
            ${m.dosage ? `<span>${esc(m.dosage)}</span>` : ""}
          </div>
        </div>
        <button class="delete" data-del="${m.id}" title="Eliminar" aria-label="Eliminar">✕</button>
      </li>`
        )
        .join("")
    : emptyState("💊", "Ningún medicamento", "Añade uno con sus horas y aparecerá en tus tomas del día.");

  wireDelete(medList, "medications");
}

async function setDoseTaken(dose, taken) {
  const fields = { taken_at: taken ? nowISO() : null, skipped: false };
  const log = dose.logId
    ? await store.update("medication_dose_logs", dose.logId, fields)
    : await store.insert("medication_dose_logs", {
        medication_id: dose.med.id,
        date: startOfToday().toISOString(),
        minute_of_day: dose.minute,
        ...fields,
      });

  // La clave lleva medicamento + hora + día: cada toma concreta se
  // premia una vez, pero dos tomas del mismo medicamento el mismo día
  // cuentan por separado.
  if (taken) {
    await awardXP(
      "medicationTaken",
      prog.dedupeKey(`dose:${idKey(dose.med.id)}:${dose.minute}`)
    );
  }
  return log;
}

$("med-form").addEventListener("submit", async (e) => {
  e.preventDefault();

  // "08:00, 20:00" → [480, 1200] (minutos desde medianoche, como en iOS).
  const minutes = $("med-times")
    .value.split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => {
      const [h, m] = s.split(":").map(Number);
      return Number.isFinite(h) && Number.isFinite(m) ? h * 60 + m : null;
    })
    .filter((m) => m !== null && m >= 0 && m < 1440)
    .sort((a, b) => a - b);

  if (!minutes.length) {
    const b = $("sync-banner");
    b.className = "banner";
    b.textContent = "Escribe al menos una hora válida, por ejemplo 08:00 o 08:00, 20:00";
    b.hidden = false;
    return;
  }

  await store.insert("medications", {
    name: $("med-name").value.trim(),
    dosage: $("med-dosage").value.trim() || null,
    reminder_minutes_since_midnight: minutes,
    is_active: true,
  });
  e.target.reset();
});

// ── Ajustes ─────────────────────────────────────────────────────────

async function loadSettings() {
  const goal = await nutritionGoal();
  $("goal-calories").value = goal?.daily_calorie_goal ?? 2000;
  $("goal-protein").value = goal?.protein_goal_grams ?? 120;
  $("goal-carbs").value = goal?.carbs_goal_grams ?? 225;
  $("goal-fat").value = goal?.fat_goal_grams ?? 65;

  const budget = await budgetSettings();
  $("budget-monthly").value = budget?.monthly_budget ?? 1000;
  $("budget-savings").value = budget?.total_savings ?? 0;
  $("budget-currency").value = budget?.currency_code ?? "EUR";

  renderAccentPicker();
  renderAIKey();
  renderSeguridad();

  const { data } = await supabase.auth.getUser();
  $("settings-email").textContent = data?.user?.email ?? "";
}

$("goal-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  await store.putSingleton("nutrition_goals", {
    daily_calorie_goal: Number($("goal-calories").value) || 2000,
    protein_goal_grams: Number($("goal-protein").value) || 0,
    carbs_goal_grams: Number($("goal-carbs").value) || 0,
    fat_goal_grams: Number($("goal-fat").value) || 0,
  });
  showSaved($("goal-form"));
});

$("budget-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  currencyCode = $("budget-currency").value;
  await store.putSingleton("budget_settings", {
    monthly_budget: Number($("budget-monthly").value) || 0,
    total_savings: Number($("budget-savings").value) || 0,
    currency_code: currencyCode,
  });
  showSaved($("budget-form"));
});

// ── Fondo ───────────────────────────────────────────────────────────
//
// Los mismos seis fondos que en iOS (BackgroundTheme.swift). Aquí solo
// están los colores de la MINIATURA: los de la página de verdad viven
// en styles.css, en los bloques [data-bg="…"]. Están duplicados a
// propósito y no leídos del CSS — sacarlos de getComputedStyle
// obligaría a pintar seis veces la página entera solo para dibujar
// seis cuadraditos.

const BACKGROUNDS = [
  { id: "system", name: "Automático", screen: "linear-gradient(90deg, #f2f2f7 0 50%, #0b0d10 50%)" },
  { id: "light", name: "Claro", screen: "#f2f2f7", card: "#ffffff" },
  { id: "cream", name: "Crema", screen: "#fbfaf7", card: "#ffffff" },
  { id: "vanilla", name: "Vainilla", screen: "#fff8e9", card: "#fffdf6" },
  { id: "graphite", name: "Grafito", screen: "#17181c", card: "#24262b" },
  { id: "night", name: "Noche", screen: "#0b0d10", card: "#16171c" },
];

const BG_KEY = "habitium.bg";

/** El fondo elegido, o "system" si no hay nada guardado o no se puede leer. */
function currentBackground() {
  try {
    const saved = localStorage.getItem(BG_KEY);
    if (BACKGROUNDS.some((b) => b.id === saved)) return saved;
  } catch (e) {
    // Almacenamiento bloqueado (modo privado en algunos navegadores).
  }
  return "night";
}

function applyBackground(id) {
  document.documentElement.setAttribute("data-bg", id);
  try {
    localStorage.setItem(BG_KEY, id);
  } catch (e) {
    // Sin guardar: el fondo aguanta esta sesión y punto. Mejor eso que
    // reventar la pantalla de Ajustes por no poder escribir.
  }
  updateThemeColor(id);
  renderBackgroundPicker();
}

/** Pinta la barra del navegador del color del fondo, no de verde.
 *  Con la app instalada en Android es la diferencia entre que se vea
 *  entera de un color o con una franja verde que no pega con nada. */
function updateThemeColor(id) {
  const meta = document.querySelector('meta[name="theme-color"]');
  if (!meta) return;
  const prefersDark = window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  const resolved = id === "system" ? (prefersDark ? "night" : "light") : id;
  meta.setAttribute("content", BACKGROUNDS.find((b) => b.id === resolved)?.screen ?? "#f2f2f7");
}

function renderBackgroundPicker() {
  const host = $("bg-picker");
  if (!host) return;
  const active = currentBackground();

  host.innerHTML = BACKGROUNDS.map(
    (b) => `
    <button class="bg-opt" type="button" data-bg-id="${b.id}"
            aria-pressed="${b.id === active}" title="${b.name}">
      <span class="bg-prev" style="background:${b.screen}">
        ${b.card ? `<span class="bg-prev-card" style="background:${b.card}"></span>` : ""}
      </span>
      <span>${b.name}</span>
    </button>`
  ).join("");

  host.querySelectorAll("[data-bg-id]").forEach((btn) => {
    btn.addEventListener("click", () => applyBackground(btn.dataset.bgId));
  });
}

// Con "Automático", seguir al sistema también cuando cambia con la app
// abierta — al anochecer, sin tocar nada.
window.matchMedia?.("(prefers-color-scheme: dark)").addEventListener?.("change", () => {
  if (currentBackground() === "system") updateThemeColor("system");
});

/** Confirmación breve en el propio botón, sin sacar un diálogo. */
function showSaved(form) {
  const btn = form.querySelector("button[type=submit]");
  const original = btn.textContent;
  btn.textContent = "Guardado ✓";
  btn.disabled = true;
  setTimeout(() => {
    btn.textContent = original;
    btn.disabled = false;
  }, 1400);
}

// ── Progresión ──────────────────────────────────────────────────────
//
// Nivel, racha, retos del día y pase. Todo esto ya existía en el iPhone;
// aquí está el mismo sistema, con los mismos números y las mismas
// claves, para que sea UNA cuenta y no dos.

/** Los identificadores dentro de una clave anti-repetición van en
 *  MAYÚSCULAS.
 *
 *  Detalle pequeño y con consecuencias grandes: en Swift, interpolar un
 *  UUID da "A1B2-…" en mayúsculas, mientras que `crypto.randomUUID()` y
 *  Postgres los dan en minúsculas. Si la web escribiera la clave en
 *  minúsculas, "habit:a1b2…:2026-09-04" y "habit:A1B2…:2026-09-04"
 *  serían dos claves distintas para el MISMO hábito del MISMO día: el
 *  iPhone y la web premiarían cada uno por su cuenta y al sincronizar
 *  saldría XP duplicado, sin ningún error que lo delatara. */
const idKey = (id) => String(id ?? "").toUpperCase();

/** Deja pasar SOLO un color hexadecimal de seis dígitos.
 *
 *  Escapar no basta cuando el destino es un atributo `style`: `esc()`
 *  neutraliza comillas y ángulos, pero no el punto y coma, así que un
 *  valor como `#fff;background-image:url('http://malo/x')` seguía siendo
 *  CSS válido y el navegador pedía esa imagen. Se comprobó atacando la
 *  app de verdad: la petición al dominio externo salía.
 *
 *  Con CSS se puede sacar información fuera (por ejemplo, con selectores
 *  de atributo que solo piden la imagen si un campo empieza por cierta
 *  letra), así que esto no es cosmético.
 *
 *  La regla: a un atributo `style` no se le escapa nada, se le valida
 *  contra una lista blanca. Si no encaja, color por defecto. */
const colorSeguro = (valor, porDefecto = "#2563eb") =>
  /^#[0-9a-fA-F]{6}$/.test(String(valor ?? "").trim()) ? String(valor).trim() : porDefecto;

/** Concede experiencia y lo celebra en pantalla. Todo lo que da puntos
 *  pasa por aquí. */
async function awardXP(source, key, date = new Date()) {
  const award = await player.award(source, key, date);
  if (award) checkChallengeBonus();
  return award;
}

/** Comprueba si los tres retos están hechos y cobra la bonificación.
 *  Se llama después de cada concesión porque cualquier acción puede
 *  haber sido la que cerró el tercer reto. */
async function checkChallengeBonus() {
  try {
    await player.awardBonusIfComplete(await challengeCounts());
  } catch (error) {
    console.warn("retos:", error);
  }
}

/** El progreso de cada tipo de reto, medido contra los datos reales de
 *  hoy. No se guarda en ningún sitio: un contador aparte sería una
 *  segunda fuente de verdad que se rompería en cuanto alguien borrase
 *  una comida. */
async function challengeCounts() {
  const today = startOfToday();
  const isToday = (value) => value && new Date(value) >= today;

  const { habits, logs } = await fetchHabits();
  const tasks = await store.all("planner_tasks");
  const completedToday = tasks.filter((t) => t.is_completed && isToday(t.updated_at));
  const { doses } = await todaysDoses();

  return {
    habits: habits.filter((h) => goalMet(h, logForToday(logs, h.id))).length,
    tasks: completedToday.length,
    focus: completedToday.filter((t) => t.is_focus).length,
    meals: (await store.all("food_entries")).filter((e) => isToday(e.date)).length,
    weight: (await store.all("weight_entries")).filter((e) => isToday(e.date)).length,
    workout: (await store.all("workout_sets")).some((s) => isToday(s.date)) ? 1 : 0,
    // Sin medicación configurada el reto no aplica; se da por cumplido
    // en vez de dejarlo imposible para siempre.
    medication: !doses.length ? 1 : doses.every((d) => d.taken || d.skipped) ? 1 : 0,
  };
}

// ── Avisos en pantalla ──────────────────────────────────────────────

let toastTimer = null;

player.onAward((award) => {
  showXPToast(award);
  if (award.didLevelUp) showLevelUp(award);
  render();
});

function showXPToast(award) {
  const source = prog.XP_SOURCES[award.source];
  const toast = $("xp-toast");
  toast.innerHTML = `<span aria-hidden="true">${source?.icon ?? "⭐"}</span>
    +${award.amount} XP <small>${esc(source?.name ?? "")}</small>`;
  toast.hidden = false;
  toast.classList.remove("is-leaving");

  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.classList.add("is-leaving");
    setTimeout(() => {
      toast.hidden = true;
      toast.classList.remove("is-leaving");
    }, 280);
  }, 2200);
}

function showLevelUp(award) {
  $("levelup-level").textContent = award.newLevel;
  $("levelup-name").textContent = prog.titleForLevel(award.newLevel);

  const rewards = award.unlockedTiers
    .map((id) => prog.SEASON_TIERS.find((t) => t.id === id))
    .filter(Boolean);
  $("levelup-rewards").innerHTML = rewards
    .map((t) => `<li>${t.icon} ${esc(prog.tierRewardName(t))}</li>`)
    .join("");

  spawnConfetti();
  $("levelup").hidden = false;
}

/** Confeti: 40 trozos con posición, color y ritmo distintos. Se generan
 *  aquí y no en CSS porque hacen falta valores aleatorios por trozo, y
 *  se borran al cerrar para no dejar 40 animaciones corriendo. */
function spawnConfetti() {
  const host = $("levelup-confetti");
  const colores = ["#7c3aed", "#15a34a", "#f59e0b", "#2563eb", "#db2777"];
  host.innerHTML = Array.from({ length: 40 }, () => {
    const left = Math.random() * 100;
    const delay = Math.random() * 0.5;
    const dur = 1.6 + Math.random() * 1.4;
    const color = colores[Math.floor(Math.random() * colores.length)];
    return `<i class="confetti-bit" style="left:${left}%;background:${color};
      animation-duration:${dur}s;animation-delay:${delay}s"></i>`;
  }).join("");
}

$("levelup-close").addEventListener("click", closeLevelUp);
$("levelup").addEventListener("click", (e) => {
  if (e.target === $("levelup")) closeLevelUp();
});

function closeLevelUp() {
  $("levelup").hidden = true;
  $("levelup-confetti").innerHTML = "";
}

// ── Acento ──────────────────────────────────────────────────────────

const ACCENT_KEY = "habitium.accent";

function currentAccent() {
  try {
    const saved = localStorage.getItem(ACCENT_KEY);
    if (saved && (prog.ACCENTS[saved] || /^#[0-9a-f]{6}$/i.test(saved))) return saved;
  } catch (e) {
    // Almacenamiento bloqueado.
  }
  return "classic";
}

function applyAccent(valor) {
  const root = document.documentElement;
  // Misma regla que con las asignaturas: lista blanca, no escapado.
  const esHex = /^#[0-9a-fA-F]{6}$/.test(String(valor ?? "").trim());

  if (esHex) {
    // Color a medida: se pisa la variable directamente. El tono suave se
    // saca del mismo color con transparencia, así que funciona igual
    // sobre fondo claro que sobre fondo oscuro sin calcular dos paletas.
    root.removeAttribute("data-accent");
    root.style.setProperty("--green", valor);
    root.style.setProperty("--green-soft", `color-mix(in srgb, ${valor} 16%, transparent)`);
  } else {
    root.style.removeProperty("--green");
    root.style.removeProperty("--green-soft");
    // El clásico no pone atributo: así el CSS de :root vale tal cual.
    if (valor === "classic") root.removeAttribute("data-accent");
    else root.setAttribute("data-accent", valor);
  }

  try {
    localStorage.setItem(ACCENT_KEY, valor);
  } catch (e) {
    // Sin guardar: aguanta esta sesión y punto.
  }
  updateThemeColor(currentBackground());
}

async function renderAccentPicker() {
  const profile = await player.profile();
  const disponibles = new Set(prog.availableAccents(profile.unlocked_reward_ids));
  const activo = currentAccent();
  const esPersonalizado = /^#[0-9a-f]{6}$/i.test(activo);
  const host = $("accent-picker");
  if (!host) return;

  const presets = Object.entries(prog.ACCENTS)
    .map(([id, a]) => {
      const libre = disponibles.has(id);
      return `<button class="accent-opt" type="button" data-accent-id="${id}"
                      aria-pressed="${id === activo}" ${libre ? "" : "disabled"}
                      title="${libre ? a.name : `${a.name} — se desbloquea en el pase`}">
                <span class="accent-dot" style="background:${a.color}">${libre ? (id === activo ? "✓" : "") : "🔒"}</span>
                <span>${a.name}</span>
              </button>`;
    })
    .join("");

  // El cuentagotas siempre está disponible, sin candado. Los temas con
  // nombre se ganan en el pase porque son identidad; poder poner TU color
  // no es un premio que haya que merecer.
  const personalizado = `
    <label class="accent-opt accent-custom" title="Tu propio color">
      <span class="accent-dot" style="background:${esPersonalizado ? activo : "conic-gradient(#f43f5e,#f59e0b,#22c55e,#3b82f6,#a855f7,#f43f5e)"}">
        ${esPersonalizado ? "✓" : ""}
      </span>
      <span>El tuyo</span>
      <input type="color" id="accent-custom" value="${esPersonalizado ? activo : "#2563eb"}">
    </label>`;

  host.innerHTML = presets + personalizado;

  host.querySelectorAll("[data-accent-id]").forEach((btn) => {
    btn.addEventListener("click", () => {
      applyAccent(btn.dataset.accentId);
      renderAccentPicker();
    });
  });
  // `input` y no `change`: el color va cambiando mientras arrastras por
  // la rueda, así se ve el efecto en la app en tiempo real.
  $("accent-custom")?.addEventListener("input", (e) => applyAccent(e.target.value));
  $("accent-custom")?.addEventListener("change", () => renderAccentPicker());
}

// ── Pantalla de Progreso ────────────────────────────────────────────

async function loadProgress() {
  const profile = await player.reconcile();
  const nivel = prog.levelForTotalXP(profile.total_xp);

  $("prog-level").textContent = nivel;
  $("prog-title").textContent = prog.highestTitle(profile.unlocked_reward_ids) ?? prog.titleForLevel(nivel);
  $("prog-detail").textContent = `${prog.xpRemainingToNextLevel(profile.total_xp)} XP para el nivel ${nivel + 1}`;
  $("prog-streak").textContent = profile.login_streak;
  $("prog-record").textContent = profile.longest_login_streak;
  $("prog-total").textContent = profile.total_xp;

  const ring = $("level-ring");
  const CIRC = 2 * Math.PI * 52;
  ring.style.strokeDasharray = String(CIRC);
  ring.style.strokeDashoffset = String(CIRC * (1 - prog.progressWithinLevel(profile.total_xp)));

  // Semana
  const semana = await player.dailyXP(7);
  // El máximo nunca baja de 20 para que un día de 5 XP no salga como
  // una barra a tope: la semana se lee comparando días, y con un solo
  // dato pequeño la escala engañaría.
  const maximo = Math.max(20, ...semana.map((d) => d.xp));
  // Altura en PÍXELES y no en porcentaje: el hueco de la barra son los
  // 116px de .xp-week menos las dos etiquetas y sus separaciones, y un
  // porcentaje dentro de un flex no tiene contra qué resolverse.
  const ALTO_MAX = 78;

  $("week-total").textContent = `${semana.reduce((s, d) => s + d.xp, 0)} XP`;
  $("xp-week").innerHTML = semana
    .map((d, i) => {
      const alto = Math.max(3, Math.round((d.xp / maximo) * ALTO_MAX));
      const hoy = i === semana.length - 1;
      const clases = ["xp-day", d.xp === 0 ? "is-empty" : "", hoy ? "is-today" : ""].join(" ");
      return `<div class="${clases}">
                <span class="xp-day-value">${d.xp || ""}</span>
                <div class="xp-bar" style="height:${alto}px"></div>
                <span class="xp-day-label">${d.date.toLocaleDateString("es-ES", { weekday: "narrow" })}</span>
              </div>`;
    })
    .join("");

  // Pase
  $("season-name").textContent = new Date().toLocaleDateString("es-ES", { month: "long" });
  $("season-xp").textContent = `${profile.season_xp} XP`;
  const siguiente = prog.nextTier(profile.season_xp);
  const desbloqueados = new Set(profile.unlocked_reward_ids);

  $("tier-list").innerHTML = prog.SEASON_TIERS.map((t) => {
    const hecho = desbloqueados.has(t.id) || profile.season_xp >= t.xpRequired;
    const esSiguiente = siguiente?.id === t.id;
    const clases = ["tier", hecho ? "is-unlocked" : "", esSiguiente ? "is-next" : ""].join(" ");
    const estado = hecho
      ? "✓"
      : esSiguiente
        ? `faltan ${t.xpRequired - profile.season_xp}`
        : "🔒";
    return `<li class="${clases}">
              <span class="tier-icon" aria-hidden="true">${t.icon}</span>
              <span class="tier-body">
                <span class="tier-name">${esc(prog.tierRewardName(t))}</span>
                <span class="tier-req">Nivel ${t.tier} del pase · ${t.xpRequired} XP</span>
              </span>
              <span class="tier-state">${estado}</span>
            </li>`;
  }).join("");

  // Historial
  const eventos = await player.recentEvents(12);
  $("xp-log").innerHTML = eventos.length
    ? eventos
        .map((e) => {
          const src = prog.XP_SOURCES[e.source];
          return `<li class="row">
                    <span aria-hidden="true">${src?.icon ?? "⭐"}</span>
                    <div class="row-main">
                      <div class="row-title">${esc(src?.name ?? e.source)}</div>
                      <div class="row-sub">${dayOf(e.date)}</div>
                    </div>
                    <span class="pill">+${e.amount}</span>
                  </li>`;
        })
        .join("")
    : emptyState("⭐", "Todavía no has ganado puntos", "Cumple un hábito o completa una tarea y verás subir el nivel.");
}




// ── Botón flotante ──────────────────────────────────────────────────
//
// En un móvil grande, el "+" de arriba obliga a recolocar la mano; esta
// esquina la alcanza el pulgar sin moverse. Lo que hace cambia según la
// pantalla: el mismo gesto, la acción que toca.

const ACCION_RAPIDA = {
  home: { destino: "nutrition", campo: "food-name", titulo: "Apuntar una comida" },
  nutrition: { campo: "food-name", titulo: "Apuntar una comida" },
  planner: { campo: "task-title", titulo: "Nueva tarea" },
  finance: { campo: "tx-amount", titulo: "Apuntar un movimiento" },
  habits: { campo: "habit-name", titulo: "Nuevo hábito" },
  medication: { campo: "med-name", titulo: "Nuevo medicamento" },
  study: { campo: "grade-name", titulo: "Apuntar una nota" },
  progress: { destino: "study", campo: "grade-name", titulo: "Apuntar una nota" },
  settings: { destino: "home", titulo: "Ir a Inicio" },
};

function refrescarFab() {
  const accion = ACCION_RAPIDA[currentView];
  const fab = $("fab");
  if (!fab) return;
  fab.title = accion?.titulo ?? "Añadir";
  fab.setAttribute("aria-label", fab.title);
}

$("fab")?.addEventListener("click", () => {
  const accion = ACCION_RAPIDA[currentView] ?? ACCION_RAPIDA.home;
  if (accion.destino && accion.destino !== currentView) go(accion.destino);

  // Un respiro antes de enfocar: si no, el teclado del móvil sube a la
  // vez que la pantalla entra y se ve un salto feo.
  setTimeout(() => {
    const campo = accion.campo && $(accion.campo);
    if (!campo) return;
    campo.scrollIntoView({ behavior: "smooth", block: "center" });
    campo.focus({ preventScroll: true });
  }, accion.destino ? 320 : 60);
});

// ── Clave de IA ─────────────────────────────────────────────────────
//
// Cada uno pone la suya. Vive en localStorage y NO viaja a Supabase, por
// la misma razón que en el iPhone: una clave de API guardada en una base
// de datos acaba replicada en copias de seguridad, y si alguien la saca
// la factura la paga su dueño.
//
// Aviso honesto que también sale en pantalla: en un navegador, "guardada
// en este dispositivo" significa que quien tenga el dispositivo
// desbloqueado puede leerla desde las herramientas de desarrollo. Es
// aceptable para tu propia clave en tu propio portátil, y es la razón de
// que Ajustes diga dónde está y no la esconda como si fuera segura.

const AI_KEY = "habitium.aikey";
const AI_PROVIDER_KEY = "habitium.aiprovider";
const AI_HELP = {
  openai: "https://platform.openai.com/api-keys",
  anthropic: "https://console.anthropic.com/settings/keys",
};

const aiProvider = () => {
  try { return localStorage.getItem(AI_PROVIDER_KEY) || "openai"; } catch (e) { return "openai"; }
};
/** Dónde guardar la clave de IA.
 *
 *  En un dispositivo compartido va a sessionStorage y muere al cerrar la
 *  pestaña. En el tuyo, a localStorage, para no tener que pegarla cada
 *  vez. Es la misma regla que para la sesión y por el mismo motivo: en
 *  el iPad del colegio, lo que sobrevive al cierre lo hereda el
 *  siguiente que se siente. */
const almacenClave = () => (dispositivoAjeno ? sessionStorage : localStorage);

const aiKeyFor = (proveedor) => {
  try { return almacenClave().getItem(`${AI_KEY}.${proveedor}`) || ""; } catch (e) { return ""; }
};

/** Solo el principio y el final: lo justo para reconocer cuál pusiste. */
const enmascarar = (clave) =>
  clave.length > 12 ? `${clave.slice(0, 6)}••••••${clave.slice(-4)}` : "•".repeat(Math.max(clave.length, 4));

function renderAIKey() {
  const host = $("ai-provider");
  if (!host) return;
  const proveedor = aiProvider();
  const clave = aiKeyFor(proveedor);

  host.value = proveedor;
  $("ai-key").value = "";
  $("ai-key").placeholder = clave ? enmascarar(clave) : proveedor === "openai" ? "sk-…" : "sk-ant-…";
  $("ai-help").href = AI_HELP[proveedor];
  $("ai-status").textContent = clave
    ? dispositivoAjeno
      ? "Clave guardada solo hasta que cierres la pestaña (marcaste dispositivo compartido)."
      : "Clave guardada en este navegador. Cualquiera que use este equipo desbloqueado puede leerla desde las herramientas de desarrollo — es el precio de no tener servidor propio."
    : "Sin clave: puedes apuntar las comidas a mano igual, pero no reconocerlas por foto.";
}

$("ai-provider")?.addEventListener("change", (e) => {
  try { localStorage.setItem(AI_PROVIDER_KEY, e.target.value); } catch (err) {}
  renderAIKey();
});

$("ai-save")?.addEventListener("click", () => {
  const clave = $("ai-key").value.trim();
  if (!clave) return;
  try { almacenClave().setItem(`${AI_KEY}.${aiProvider()}`, clave); } catch (e) {}
  renderAIKey();
  $("ai-status").textContent = "Guardada ✓";
});

$("ai-clear")?.addEventListener("click", () => {
  try { almacenClave().removeItem(`${AI_KEY}.${aiProvider()}`); } catch (e) {}
  renderAIKey();
});

// ── Ajustes → Seguridad ─────────────────────────────────────────────
//
// Dos cosas, y las dos son las que de verdad evitan que te roben la
// cuenta: la verificación en dos pasos y poder cambiar la contraseña sin
// pasar por el correo.
//
// Lo del alta en dos tiempos (primero el QR, después confirmarlo con un
// código) no es burocracia: si se activara de golpe y el móvil no hubiera
// guardado bien el secreto, te quedarías fuera de tu propia cuenta sin
// forma de volver a entrar.

let altaMFA = null;   // { factorId, qr, secreto } mientras se está dando de alta

function mensajeSeguridad(texto, ok = false) {
  const el = $("sec-status");
  if (!el) return;
  el.textContent = texto;
  el.classList.toggle("is-ok", ok);
}

async function renderSeguridad() {
  if (!$("sec-state")) return;
  let factores = [];
  try {
    factores = await seg.factoresActivos(supabase);
  } catch (e) {
    $("sec-state").textContent = "No se ha podido comprobar (sin conexión).";
    return;
  }

  const activa = factores.length > 0;
  $("sec-state").textContent = activa
    ? "Activada. Para entrar hacen falta la contraseña y el código de tu móvil."
    : "Desactivada. Ahora mismo basta con tu contraseña para entrar.";
  $("sec-state").classList.toggle("is-ok", activa);
  $("sec-enable").hidden = activa || !!altaMFA;
  $("sec-disable").hidden = !activa;
  $("sec-enroll").hidden = !altaMFA;
  $("sec-disable").dataset.factor = activa ? factores[0].id : "";
}

$("sec-enable")?.addEventListener("click", async () => {
  mensajeSeguridad("");
  $("sec-enable").disabled = true;
  try {
    altaMFA = await seg.empezarAltaMFA(supabase);
    // El QR viene ya dibujado desde Supabase (un SVG dentro de un data:).
    // Por eso no hace falta ninguna librería de fuera — y por eso la
    // Content-Security-Policy se queda como está.
    $("sec-qr").src = altaMFA.qr;
    $("sec-secret").textContent = altaMFA.secreto;
    $("sec-code").value = "";
    await renderSeguridad();
    $("sec-code").focus();
  } catch (error) {
    mensajeSeguridad(seg.mensajeDeError(error));
  } finally {
    $("sec-enable").disabled = false;
  }
});

$("sec-enroll")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!altaMFA) return;
  mensajeSeguridad("");
  try {
    await seg.confirmarAltaMFA(supabase, altaMFA.factorId, $("sec-code").value);
    altaMFA = null;
    $("sec-qr").src = "";
    $("sec-secret").textContent = "";
    await renderSeguridad();
    mensajeSeguridad("Listo. A partir de ahora te pedirá el código al entrar.", true);
  } catch (error) {
    mensajeSeguridad(seg.mensajeDeError(error));
  }
});

$("sec-enroll-cancel")?.addEventListener("click", async () => {
  // Cancelar tiene que DESHACER el alta en el servidor. Si solo se
  // ocultara el formulario quedaría un factor a medias dando guerra la
  // próxima vez que se intente activar.
  if (altaMFA) {
    try { await seg.quitarMFA(supabase, altaMFA.factorId); } catch (e) {}
    altaMFA = null;
  }
  $("sec-qr").src = "";
  $("sec-secret").textContent = "";
  await renderSeguridad();
  mensajeSeguridad("");
});

$("sec-disable")?.addEventListener("click", async () => {
  const id = $("sec-disable").dataset.factor;
  if (!id) return;
  if (!confirm("¿Seguro? Sin verificación en dos pasos, quien sepa tu contraseña entra en tu cuenta.")) return;
  try {
    await seg.quitarMFA(supabase, id);
    await renderSeguridad();
    mensajeSeguridad("Verificación en dos pasos desactivada.");
  } catch (error) {
    mensajeSeguridad(seg.mensajeDeError(error));
  }
});

$("password-form")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const nueva = $("password-new").value;
  const repetida = $("password-repeat").value;
  const email = $("side-email").textContent;

  if (nueva !== repetida) return mensajeSeguridad("Las dos contraseñas no son iguales.");
  const problema = seg.problemaContrasena(nueva, email);
  if (problema) return mensajeSeguridad(problema);

  const { error } = await supabase.auth.updateUser({ password: nueva });
  if (error) return mensajeSeguridad(seg.mensajeDeError(error));

  $("password-new").value = "";
  $("password-repeat").value = "";
  mensajeSeguridad("Contraseña cambiada. Las sesiones de otros dispositivos seguirán abiertas hasta que cierres sesión en ellos.", true);
});

$("password-new")?.addEventListener("input", () => {
  const barra = $("password-strength");
  if (!barra) return;
  const valor = $("password-new").value;
  barra.hidden = !valor;
  if (!valor) return;
  const { nivel, texto } = seg.fuerzaContrasena(valor, $("side-email").textContent);
  barra.dataset.nivel = String(nivel);
  $("password-strength-text").textContent = texto;
});

// ── Rutinas encadenadas ─────────────────────────────────────────────
//
// El caso que las pide: "a las 7:15 me levanto, luego me ducho, luego me
// lavo los dientes, luego desayuno". Todo el cálculo de horarios está en
// routines.js y probado aparte; aquí solo se pinta y se guarda.
//
// Lo único con enjundia de este archivo es `reprogramarAvisos()`: cada
// vez que cambia algo hay que rehacer los avisos ENTEROS, porque marcar
// un paso mueve en cascada todos los que vienen detrás.

/** La rutina que tiene los pasos desplegados. Se recuerda entre
 *  repintados para que marcar un paso no te cierre la lista en la cara. */
let rutinaAbierta = null;

async function datosDeRutinas() {
  const [routines, steps, logs] = await Promise.all([
    store.all("routines"),
    store.all("routine_steps"),
    store.all("routine_logs"),
  ]);
  routines.sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0) || (a.start_minutes ?? 0) - (b.start_minutes ?? 0));
  return { routines, steps, logs };
}

/** Rehace los avisos desde cero con el estado actual. Se llama SIEMPRE
 *  después de tocar cualquier cosa: una rutina, un paso o una marca. */
async function reprogramarAvisos() {
  try {
    avisos.reprogramar(await datosDeRutinas());
  } catch (error) {
    console.warn("avisos:", error);
  }
}

async function loadRoutines() {
  pintarPermisoAvisos();

  const { routines, steps, logs } = await datosDeRutinas();
  const ahora = new Date();

  $("routines-empty").hidden = routines.length > 0;
  $("routines-list").innerHTML = routines
    .map((r) => tarjetaDeRutina(r, steps, logs, ahora))
    .join("");

  cablearRutinas(routines, steps);
  avisos.reprogramar({ routines, steps, logs }, ahora);
}

function tarjetaDeRutina(routine, steps, logs, ahora) {
  const pasos = rut.horario(routine, steps, logs, ahora);
  const { hechos, total } = rut.progreso(routine, steps, logs, ahora);
  const dias = rut.racha(routine, steps, logs, ahora);
  const abierta = rutinaAbierta === routine.id;
  const hoyToca = rut.tocaHoy(routine, ahora);

  return `
  <article class="card routine ${hoyToca ? "" : "is-off"} ${total && hechos === total ? "is-done" : ""}">
    <header class="card-head">
      <span class="card-head-inner">
        <span class="badge" aria-hidden="true">${esc(routine.icon ?? "🔁")}</span>
        <h2>${esc(routine.name)}</h2>
      </span>
      <span class="routine-meta">
        ${dias > 0 ? `<span class="pill streak">🔥 ${dias}</span>` : ""}
        <span class="pill">${hechos}/${total}</span>
      </span>
    </header>

    <p class="routine-summary">${esc(rut.resumen(routine, steps, logs, ahora))}</p>

    ${total ? `<div class="routine-bar" role="img" aria-label="${hechos} de ${total} pasos">
      <i style="width:${total ? Math.round((hechos / total) * 100) : 0}%"></i>
    </div>` : ""}

    <ol class="routine-steps">
      ${pasos.map((f) => filaDePaso(routine, f)).join("")}
    </ol>

    <div class="routine-actions">
      <button class="btn btn-ghost btn-sm" data-routine-toggle="${routine.id}">
        ${abierta ? "Cerrar ajustes" : "Ajustes de la rutina"}
      </button>
    </div>

    ${abierta ? ajustesDeRutina(routine, steps) : ""}
  </article>`;
}

function filaDePaso(routine, fila) {
  const { paso, hecho, enMarcha, hora, previsto } = fila;
  const h = `${hora.getHours()}:${String(hora.getMinutes()).padStart(2, "0")}`;

  return `
  <li class="routine-step ${hecho ? "is-done" : ""} ${enMarcha ? "is-now" : ""}">
    <button class="check ${hecho ? "is-checked" : ""}"
            data-step-toggle="${paso.id}" data-routine="${routine.id}" data-done="${hecho}"
            aria-label="${hecho ? "Desmarcar" : "Marcar"} ${esc(paso.title)}">✓</button>
    <span class="routine-step-icon" aria-hidden="true">${esc(paso.icon ?? "✅")}</span>
    <div class="routine-step-main">
      <div class="routine-step-title">${esc(paso.title)}</div>
      <div class="routine-step-sub">
        ${hecho ? `hecho a las ${h}` : `${h}${previsto ? "" : " · recalculado"} · ${paso.duration_minutes} min`}
      </div>
    </div>
    ${fila.esAhora ? '<span class="pill now">ahora</span>' : ""}
  </li>`;
}

function ajustesDeRutina(routine, steps) {
  const pasos = rut.pasosDe(routine, steps);
  const dias = routine.days_of_week ?? [];

  return `
  <div class="routine-settings">
    <div class="form-grid">
      <label class="field"><span>Empieza a las</span>
        <input type="time" data-routine-start="${routine.id}"
               value="${String(Math.floor((routine.start_minutes ?? 0) / 60)).padStart(2, "0")}:${String((routine.start_minutes ?? 0) % 60).padStart(2, "0")}">
      </label>
      <label class="field"><span>Nombre</span>
        <input type="text" maxlength="120" data-routine-name="${routine.id}" value="${esc(routine.name)}">
      </label>
    </div>

    <div class="day-picker" role="group" aria-label="Días de la semana">
      ${rut.NOMBRES_DIA.map((nombre, i) => `
        <button type="button" class="day ${dias.includes(i + 1) ? "is-on" : ""}"
                data-routine-day="${routine.id}" data-day="${i + 1}"
                aria-pressed="${dias.includes(i + 1)}">${nombre}</button>`).join("")}
    </div>

    <label class="shared-check">
      <input type="checkbox" data-routine-notify="${routine.id}" ${routine.notifications_enabled ? "checked" : ""}>
      <span>Avisarme de cada paso <small>Solo mientras Habitium esté abierta en este dispositivo.</small></span>
    </label>

    <h3 class="routine-subhead">Pasos</h3>
    <ul class="list">
      ${pasos.map((p) => `
        <li class="row">
          <span class="routine-step-icon" aria-hidden="true">${esc(p.icon ?? "✅")}</span>
          <div class="row-main">
            <div class="row-title">${esc(p.title)}</div>
            <div class="row-sub"><span>${p.duration_minutes} min</span></div>
          </div>
          <button class="delete" data-step-del="${p.id}" title="Eliminar paso" aria-label="Eliminar paso">✕</button>
        </li>`).join("") || emptyState("🪜", "Sin pasos todavía", "Añade el primero abajo.")}
    </ul>

    <form class="composer-row" data-step-form="${routine.id}">
      <input type="text" name="titulo" placeholder="Nuevo paso" maxlength="120" required>
      <input type="text" name="icono" class="w-xs" placeholder="✅" maxlength="2">
      <input type="number" name="minutos" class="w-sm" min="1" max="720" step="1" value="10" required>
      <button class="btn btn-primary" type="submit">Añadir</button>
    </form>

    <button class="btn btn-ghost danger btn-sm" data-routine-del="${routine.id}">Eliminar esta rutina</button>
  </div>`;
}

function cablearRutinas(routines, steps) {
  const lista = $("routines-list");

  // Marcar / desmarcar un paso.
  lista.querySelectorAll("[data-step-toggle]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const stepId = btn.dataset.stepToggle;
      const routineId = btn.dataset.routine;

      if (btn.dataset.done === "true") {
        // Desmarcar: fuera TODAS las marcas de hoy de ese paso. Si se
        // borrara solo una, una marca duplicada de otro dispositivo lo
        // dejaría marcado y parecería que el botón no hace nada.
        const hoy = new Date();
        for (const log of await store.all("routine_logs")) {
          if (log.step_id !== stepId) continue;
          const d = new Date(log.date);
          if (d.toDateString() === hoy.toDateString()) await store.remove("routine_logs", log.id);
        }
      } else {
        await store.insert("routine_logs", {
          routine_id: routineId,
          step_id: stepId,
          date: nowISO(),
        });

        // XP solo al terminar la rutina entera, no por paso: si cada paso
        // diera puntos, crear una rutina de veinte pasos tontos sería la
        // forma más rápida de subir de nivel.
        const { routines: rs, steps: ss, logs: ls } = await datosDeRutinas();
        const routine = rs.find((r) => r.id === routineId);
        if (routine && rut.completa(routine, ss, ls)) {
          await awardXP("routineCompleted", `rutina:${idKey(routineId)}:${rut.claveDia(new Date())}`);
        }
      }
      await reprogramarAvisos();
    });
  });

  // Abrir / cerrar los ajustes.
  lista.querySelectorAll("[data-routine-toggle]").forEach((btn) => {
    btn.addEventListener("click", () => {
      rutinaAbierta = rutinaAbierta === btn.dataset.routineToggle ? null : btn.dataset.routineToggle;
      loadRoutines();
    });
  });

  lista.querySelectorAll("[data-routine-start]").forEach((input) => {
    input.addEventListener("change", async () => {
      const minutos = rut.minutosDesdeTexto(input.value);
      if (minutos === null) return;
      await store.update("routines", input.dataset.routineStart, { start_minutes: minutos });
      await reprogramarAvisos();
    });
  });

  lista.querySelectorAll("[data-routine-name]").forEach((input) => {
    input.addEventListener("change", async () => {
      const nombre = input.value.trim();
      if (nombre) await store.update("routines", input.dataset.routineName, { name: nombre });
    });
  });

  lista.querySelectorAll("[data-routine-day]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const routine = routines.find((r) => r.id === btn.dataset.routineDay);
      if (!routine) return;
      const dia = Number(btn.dataset.day);
      const actuales = new Set(routine.days_of_week ?? []);
      actuales.has(dia) ? actuales.delete(dia) : actuales.add(dia);
      await store.update("routines", routine.id, { days_of_week: [...actuales].sort() });
      await reprogramarAvisos();
    });
  });

  lista.querySelectorAll("[data-routine-notify]").forEach((input) => {
    input.addEventListener("change", async () => {
      await store.update("routines", input.dataset.routineNotify, {
        notifications_enabled: input.checked,
      });
      if (input.checked && avisos.estadoPermiso() === "default") await pedirAvisos();
      await reprogramarAvisos();
    });
  });

  lista.querySelectorAll("[data-step-form]").forEach((form) => {
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const routineId = form.dataset.stepForm;
      const titulo = form.titulo.value.trim();
      if (!titulo) return;

      await store.insert("routine_steps", {
        routine_id: routineId,
        title: titulo,
        icon: form.icono.value.trim() || "✅",
        duration_minutes: Math.min(720, Math.max(1, Number(form.minutos.value) || 10)),
        sort_order: rut.pasosDe({ id: routineId }, steps).length,
      });
      form.reset();
      form.minutos.value = "10";
      await reprogramarAvisos();
    });
  });

  lista.querySelectorAll("[data-step-del]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await store.remove("routine_steps", btn.dataset.stepDel);
      await reprogramarAvisos();
    });
  });

  lista.querySelectorAll("[data-routine-del]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!confirm("¿Eliminar la rutina entera, con sus pasos?")) return;
      rutinaAbierta = null;
      await store.remove("routines", btn.dataset.routineDel);
      await reprogramarAvisos();
    });
  });
}

// ── Crear rutinas ───────────────────────────────────────────────────

$("routine-form")?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const nombre = $("routine-name").value.trim();
  if (!nombre) return;

  const routine = await store.insert("routines", {
    name: nombre,
    icon: $("routine-icon").value.trim() || "🔁",
    start_minutes: rut.minutosDesdeTexto($("routine-start").value) ?? 435,
    days_of_week: [1, 2, 3, 4, 5],
    is_active: true,
    notifications_enabled: true,
    sort_order: (await store.all("routines")).length,
    created_at: nowISO(),
  });

  e.target.reset();
  $("routine-start").value = "07:15";
  // Se abre sola: una rutina sin pasos no sirve de nada, así que lo
  // siguiente que hay que hacer es añadirlos.
  rutinaAbierta = routine.id;
  if (avisos.estadoPermiso() === "default") await pedirAvisos();
});

/** Crea una rutina entera desde una plantilla. Ofrecerla es lo que
 *  diferencia "aquí tienes un formulario vacío" de "toma, esto ya es
 *  tu rutina de mañana, cámbiala a tu gusto". */
async function crearDesdePlantilla(plantilla) {
  const routine = await store.insert("routines", {
    name: plantilla.name,
    icon: plantilla.icon,
    start_minutes: plantilla.start_minutes,
    days_of_week: plantilla.days_of_week,
    is_active: true,
    notifications_enabled: true,
    sort_order: (await store.all("routines")).length,
    created_at: nowISO(),
  });

  for (const [i, paso] of plantilla.pasos.entries()) {
    await store.insert("routine_steps", {
      routine_id: routine.id,
      title: paso.title,
      icon: paso.icon,
      duration_minutes: paso.duration_minutes,
      sort_order: i,
    });
  }

  if (avisos.estadoPermiso() === "default") await pedirAvisos();
  await reprogramarAvisos();
}

$("routine-template-morning")?.addEventListener("click", () => crearDesdePlantilla(rut.PLANTILLA_MANANA));
$("routine-template-night")?.addEventListener("click", () => crearDesdePlantilla(rut.PLANTILLA_NOCHE));

// ── Permiso de avisos ───────────────────────────────────────────────

/** Se pone a true justo después de conceder el permiso, para que la caja
 *  de avisos no desaparezca en el mismo instante en que dices que sí:
 *  hay que poder ver el botón de "Probar". */
let avisoRecienDado = false;

function pintarPermisoAvisos() {
  const caja = $("routines-permission");
  if (!caja) return;

  const estado = avisos.estadoPermiso();
  $("routines-permission-text").textContent = avisos.explicacion();
  $("routines-permission-ask").hidden = estado !== "default";
  $("routines-permission-test").hidden = estado !== "granted";

  // Con el permiso dado y todo funcionando, la caja estorba. Se queda
  // solo si hay algo que hacer o algo que explicar.
  caja.hidden = estado === "granted" && !avisoRecienDado;
}

async function pedirAvisos() {
  const resultado = await avisos.pedirPermiso();
  avisoRecienDado = resultado === "granted";
  pintarPermisoAvisos();
  await reprogramarAvisos();
  return resultado;
}

$("routines-permission-ask")?.addEventListener("click", pedirAvisos);
$("routines-permission-test")?.addEventListener("click", () => avisos.avisoDePrueba());

// ── Estudios ────────────────────────────────────────────────────────
//
// El módulo que cierra la idea original del sistema de niveles: "cada
// día que inicies sesión, luego que saques buenas notas, etc., vas a
// subir de nivel". Hasta ahora la parte de las notas no existía.
//
// Todo lo que se calcula (media, asistencia, cuenta atrás) vive en
// study.js y está probado aparte. Aquí solo se pinta.

/** La asignatura abierta en la calculadora. Se recuerda entre repintados
 *  para que apuntar una nota no te devuelva a la primera de la lista. */
let subjectAbierta = null;

const PALETA_ASIGNATURAS = ["#2563eb", "#db2777", "#ea580c", "#15a34a", "#7c3aed", "#0891b2", "#ca8a04"];

async function loadStudy() {
  const subjects = (await store.all("subjects")).sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
  const grades = await store.all("grades");
  const events = await store.all("study_events");

  if (!subjects.some((s) => s.id === subjectAbierta)) {
    subjectAbierta = subjects[0]?.id ?? null;
  }

  renderStudyEvents(events, subjects);
  renderSubjects(subjects, grades);
  renderGrades(subjects, grades);
  renderAttendance(subjects, grades);
}

function renderStudyEvents(events, subjects) {
  const proximos = study.upcoming(events);
  const nombre = (id) => subjects.find((s) => s.id === id)?.name ?? "";

  $("study-events").innerHTML = proximos.length
    ? proximos
        .map((e) => {
          const tipo = study.eventKind(e.kind);
          const dias = study.daysUntil(e.date);
          const clase = dias <= 1 ? "is-now" : dias <= 5 ? "is-soon" : "";
          return `<li class="row">
                    <div class="row-icon">${tipo.icon}</div>
                    <div class="row-main">
                      <div class="row-title">${esc(e.title)}</div>
                      <div class="row-sub">
                        <span class="tag ${tipo.tone}">${tipo.label}</span>
                        ${e.subject_id ? `<span>${esc(nombre(e.subject_id))}</span>` : ""}
                        <span>${dayOf(e.date)}</span>
                      </div>
                    </div>
                    <span class="countdown ${clase}">${study.countdownLabel(e.date)}</span>
                    <button class="delete" data-del-event="${e.id}" title="Eliminar">✕</button>
                  </li>`;
        })
        .join("")
    : emptyState("🗓️", "Nada a la vista", "Apunta tu próximo examen o entrega y verás la cuenta atrás.");

  $("study-events").querySelectorAll("[data-del-event]").forEach((b) => {
    b.addEventListener("click", () => store.remove("study_events", b.dataset.delEvent));
  });
}

function renderSubjects(subjects, grades) {
  const host = $("subject-grid");
  if (!subjects.length) {
    host.innerHTML = `<div class="empty"><span class="empty-icon">🎓</span>
      <span class="empty-title">Aún no hay asignaturas</span>
      <span class="empty-hint">Añade la primera abajo y podrás llevar sus notas y sus faltas.</span></div>`;
    $("study-overall").textContent = "—";
    return;
  }

  const medias = subjects
    .map((s) => study.weightedAverage(grades.filter((g) => g.subject_id === s.id)))
    .filter((m) => m !== null);
  $("study-overall").textContent = medias.length
    ? `${(medias.reduce((a, b) => a + b, 0) / medias.length).toFixed(2)} de media`
    : "sin notas";

  host.innerHTML = subjects
    .map((s) => {
      const suyas = grades.filter((g) => g.subject_id === s.id);
      const media = study.weightedAverage(suyas);
      const estado = study.subjectStatus(s, suyas);
      const cubierto = Math.round(study.weightCovered(suyas) * 100);
      return `<button class="subject ${s.id === subjectAbierta ? "is-active" : ""}" type="button"
                      data-subject="${s.id}" style="--subject-color:${colorSeguro(s.color)}">
                <span class="subject-top">
                  <span class="subject-icon" aria-hidden="true">${s.icon || "📘"}</span>
                  <span class="subject-name">${esc(s.name)}</span>
                  <span class="subject-mark" style="color:${media === null ? "var(--text-3)" : media < study.PASS_MARK ? "var(--red)" : "var(--green)"}">
                    ${media === null ? "—" : media.toFixed(1)}
                  </span>
                </span>
                <span class="subject-meta">
                  <span class="tag ${estado.tone}">${estado.label}</span>
                  <span class="tag muted">${cubierto} % evaluado</span>
                </span>
              </button>`;
    })
    .join("");

  host.querySelectorAll("[data-subject]").forEach((b) => {
    b.addEventListener("click", () => {
      subjectAbierta = b.dataset.subject;
      loadStudy();
    });
  });
}

function renderGrades(subjects, grades) {
  const asignatura = subjects.find((s) => s.id === subjectAbierta);
  $("grades-card").hidden = !asignatura;
  if (!asignatura) return;

  const suyas = grades
    .filter((g) => g.subject_id === asignatura.id)
    .sort((a, b) => new Date(a.date) - new Date(b.date));

  $("grades-subject-name").textContent = asignatura.name;
  $("grades-body").innerHTML = suyas.length
    ? suyas
        .map(
          (g) => `<tr class="${g.counts_for_average ? "" : "is-out"}">
            <td class="grade-name">${esc(g.name)}</td>
            <td class="num"><span class="grade-score ${Number(g.score) < study.PASS_MARK ? "is-fail" : "is-pass"}">${Number(g.score).toFixed(2).replace(/\.?0+$/, "")}</span></td>
            <td class="num">${Number(g.weight)} %</td>
            <td class="num">${study.weightedPoints(g).toFixed(2)}</td>
            <td class="mid"><input type="checkbox" data-count="${g.id}" ${g.counts_for_average ? "checked" : ""} aria-label="Cuenta para la media"></td>
            <td class="mid"><button class="delete" data-del-grade="${g.id}" title="Eliminar">✕</button></td>
          </tr>`
        )
        .join("")
    : `<tr><td colspan="6" class="muted sm" style="padding:14px 8px">Sin notas todavía. Apunta la primera abajo.</td></tr>`;

  const media = study.weightedAverage(suyas);
  const falta = study.neededInRemaining(suyas, 5);
  const partes = [];
  if (media !== null) partes.push(`Media de lo evaluado: ${media.toFixed(2)}`);
  partes.push(`Llevas ${study.pointsSoFar(suyas).toFixed(2)} puntos de 10`);
  if (falta !== null && falta > 0) {
    partes.push(
      falta > 10
        ? "Con lo que queda ya no da para el 5 — habla con el profesor"
        : `Necesitas un ${falta.toFixed(1)} en lo que queda para aprobar`
    );
  }
  $("grade-summary").textContent = partes.join(" · ");

  $("grades-body").querySelectorAll("[data-del-grade]").forEach((b) => {
    b.addEventListener("click", () => store.remove("grades", b.dataset.delGrade));
  });
  $("grades-body").querySelectorAll("[data-count]").forEach((c) => {
    c.addEventListener("change", () =>
      store.update("grades", c.dataset.count, { counts_for_average: c.checked })
    );
  });
}

function renderAttendance(subjects, grades) {
  const conClases = subjects.filter((s) => (Number(s.total_classes) || 0) > 0);
  $("attendance-list").innerHTML = conClases.length
    ? conClases
        .map((s) => {
          const pct = study.attendance(s) ?? 100;
          const quedan = study.absencesLeft(s);
          const clase = pct < 75 ? "is-bad" : pct < 85 ? "is-warn" : "";
          return `<li class="row">
                    <div class="row-icon">${s.icon || "📘"}</div>
                    <div class="row-main">
                      <div class="row-title">${esc(s.name)}</div>
                      <div class="row-sub">
                        <span>${s.hours_missed || 0} de ${s.total_classes} h faltadas</span>
                        ${quedan === null ? "" : `<span class="tag ${quedan < 0 ? "danger" : quedan <= 2 ? "warn" : "muted"}">${quedan < 0 ? `${Math.abs(quedan)} h pasado` : `te quedan ${quedan} h`}</span>`}
                      </div>
                      <span class="att-bar"><span class="att-fill ${clase}" style="width:${pct}%"></span></span>
                    </div>
                    <div class="row-value">${Math.round(pct)} %</div>
                    <button class="btn btn-ghost btn-sm" data-miss="${s.id}" title="Sumar una hora faltada">+1 falta</button>
                  </li>`;
        })
        .join("")
    : emptyState("📍", "Sin asistencia que seguir", "Pon el número de clases de una asignatura y llevaremos la cuenta.");

  $("attendance-list").querySelectorAll("[data-miss]").forEach((b) => {
    b.addEventListener("click", async () => {
      const s = subjects.find((x) => x.id === b.dataset.miss);
      if (s) await store.update("subjects", s.id, { hours_missed: (Number(s.hours_missed) || 0) + 1 });
    });
  });
}

$("subject-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const existentes = await store.all("subjects");
  await store.insert("subjects", {
    name: $("subject-name").value.trim(),
    icon: $("subject-icon").value.trim() || "📘",
    color: PALETA_ASIGNATURAS[existentes.length % PALETA_ASIGNATURAS.length],
    teacher: null,
    total_classes: Number($("subject-classes").value) || 0,
    hours_missed: 0,
    max_absences: Number($("subject-max").value) || 0,
    sort_order: existentes.length,
  });
  e.target.reset();
});

$("grade-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!subjectAbierta) return;

  const score = Number($("grade-score").value);
  const fila = await store.insert("grades", {
    subject_id: subjectAbierta,
    name: $("grade-name").value.trim(),
    score,
    weight: Number($("grade-weight").value) || 0,
    counts_for_average: true,
    date: nowISO(),
  });
  e.target.reset();

  // Apuntar da poco; sacar buena nota da bastante. Si diera lo mismo, lo
  // rentable sería inventarse pruebas en vez de estudiar.
  await awardXP("gradeLogged", `grade:${idKey(fila.id)}`);
  if (score >= 7) await awardXP("goodGrade", `goodgrade:${idKey(fila.id)}`);

  // Y si con esta nota la asignatura pasa a estar aprobada, se premia
  // una vez por asignatura y mes: es un logro real, no una tirada.
  const suyas = (await store.all("grades")).filter((g) => g.subject_id === subjectAbierta);
  const media = study.weightedAverage(suyas);
  if (media !== null && media >= study.PASS_MARK) {
    await awardXP("subjectPassing", `passing:${idKey(subjectAbierta)}:${prog.currentSeasonID()}`);
  }
});

$("study-add-event").addEventListener("click", async () => {
  const title = prompt("¿Qué es? (ej: Examen de Estadística)");
  if (!title) return;
  const cuando = prompt("¿Qué día? (dd/mm/aaaa)");
  if (!cuando) return;
  const [d, m, a] = cuando.split(/[\/\-\.]/).map(Number);
  const fecha = new Date(a ?? new Date().getFullYear(), (m ?? 1) - 1, d ?? 1, 9);
  if (Number.isNaN(fecha.getTime())) return;

  await store.insert("study_events", {
    subject_id: subjectAbierta,
    title: title.trim(),
    kind: /examen|parcial|final/i.test(title) ? "exam" : /entrega|trabajo/i.test(title) ? "assignment" : "exam",
    date: fecha.toISOString(),
    notes: null,
  });
});

// ── Inicio ──────────────────────────────────────────────────────────

async function loadHome() {
  await loadHomeProgression();

  const entries = await todaysFood();
  const goal = await nutritionGoal();
  const budget = await budgetSettings();
  const txs = await monthTransactions();

  // Anillo de calorías
  const consumed = entries.reduce((s, e) => s + (e.calories ?? 0), 0);
  const goalCal = goal?.daily_calorie_goal ?? 2000;
  $("home-calories").textContent = Math.round(goalCal - consumed);
  $("home-calories-detail").textContent =
    `${Math.round(consumed)} de ${Math.round(goalCal)} kcal · ${entries.length} comidas`;

  const ratio = goalCal > 0 ? Math.min(1, consumed / goalCal) : 0;
  const ring = $("ring-progress");
  const CIRCUMFERENCE = 2 * Math.PI * 52;
  ring.style.strokeDashoffset = String(CIRCUMFERENCE * (1 - ratio));
  ring.classList.toggle("is-over", consumed > goalCal);

  // Macros
  const sum = (key) => entries.reduce((s, e) => s + (e[key] ?? 0), 0);
  const macros = [
    { name: "Proteína", got: sum("protein_grams"), target: goal?.protein_goal_grams ?? 0 },
    { name: "Carbos", got: sum("carbs_grams"), target: goal?.carbs_goal_grams ?? 0 },
    { name: "Grasas", got: sum("fat_grams"), target: goal?.fat_goal_grams ?? 0 },
  ];
  $("home-macros").innerHTML = macros
    .map(
      (m) => `
      <div class="macro">
        <div class="macro-name">${m.name}</div>
        <div class="track"><div class="track-fill" style="width:${m.target ? Math.min(100, (m.got / m.target) * 100) : 0}%"></div></div>
        <div class="macro-val">${Math.round(m.got)}${m.target ? ` / ${Math.round(m.target)}` : ""} g</div>
      </div>`
    )
    .join("");

  // Hábitos
  const { habits, logs } = await fetchHabits();
  const met = habits.filter((h) => goalMet(h, logForToday(logs, h.id))).length;
  $("home-habits").textContent = habits.length ? `${met}/${habits.length}` : "—";
  $("home-habits-detail").textContent = habits.length
    ? met === habits.length
      ? "¡Todos cumplidos hoy!"
      : "Cumplidos hoy"
    : "Aún no tienes hábitos.";
  $("home-habits-bar").style.width = habits.length ? `${(met / habits.length) * 100}%` : "0%";

  // Presupuesto
  const spent = txs.filter((t) => t.type === "expense").reduce((s, t) => s + t.amount, 0);
  const monthly = budget?.monthly_budget ?? 0;
  $("home-available").textContent = money(Math.max(0, monthly - spent));
  $("home-available-detail").textContent = `${money(spent)} gastado de ${money(monthly)}`;
  const budgetBar = $("home-budget-bar");
  budgetBar.style.width = monthly ? `${Math.min(100, (spent / monthly) * 100)}%` : "0%";
  budgetBar.classList.toggle("is-over", spent > monthly);

  // Próxima tarea
  const today = startOfToday();
  const next = (await store.all("planner_tasks"))
    .filter((t) => !t.is_completed && t.due_date && new Date(t.due_date) >= today)
    .sort((a, b) => new Date(a.due_date) - new Date(b.due_date))[0];
  $("home-next").textContent = next?.title ?? "Nada pendiente";
  $("home-next-detail").textContent = next?.due_date ? dayOf(next.due_date) : "";

  // Estudios: lo más cercano manda. Un examen dentro de tres días es
  // más urgente que la media del curso, y es lo que quieres ver al abrir.
  const subjects = await store.all("subjects");
  const proximo = study.upcoming(await store.all("study_events"), new Date(), 1)[0];
  if (proximo) {
    $("home-study").textContent = study.countdownLabel(proximo.date);
    $("home-study-detail").textContent = `${study.eventKind(proximo.kind).label} · ${proximo.title}`;
  } else if (subjects.length) {
    const todas = await store.all("grades");
    const medias = subjects
      .map((s) => study.weightedAverage(todas.filter((g) => g.subject_id === s.id)))
      .filter((m) => m !== null);
    $("home-study").textContent = medias.length
      ? (medias.reduce((a, b) => a + b, 0) / medias.length).toFixed(2)
      : "—";
    $("home-study-detail").textContent = medias.length ? "de media este curso" : "Aún sin notas";
  } else {
    $("home-study").textContent = "—";
    $("home-study-detail").textContent = "Añade tus asignaturas";
  }

  // Próxima toma
  const { doses } = await todaysDoses();
  const pending = doses.find((d) => !d.taken && !d.skipped);
  $("home-dose").textContent = pending ? pending.med.name : "Sin tomas pendientes";
  $("home-dose-detail").textContent = pending
    ? `${minutesToTime(pending.minute)}${pending.med.dosage ? " · " + pending.med.dosage : ""}`
    : "";
}

/** La tarjeta de nivel y los retos, arriba de Inicio. */
async function loadHomeProgression() {
  // Antes de pintar, recalcular el total desde los eventos: así se
  // recoge el XP ganado en el iPhone en cuanto ha sincronizado, sin
  // depender de qué perfil ganó la última escritura. Solo escribe si
  // algo cambió, así que la segunda pasada no hace nada.
  const profile = await player.reconcile();
  const nivel = prog.levelForTotalXP(profile.total_xp);

  $("home-level").textContent = nivel;
  $("home-level-title").textContent =
    prog.highestTitle(profile.unlocked_reward_ids) ?? prog.titleForLevel(nivel);
  $("home-level-bar").style.width = `${prog.progressWithinLevel(profile.total_xp) * 100}%`;
  $("home-level-detail").textContent = `${prog.xpRemainingToNextLevel(profile.total_xp)} XP para el nivel ${nivel + 1}`;

  // La racha solo se enseña si existe: un "🔥 0" es un recordatorio de
  // que no tienes racha, que es justo lo contrario de lo que hace un
  // contador de rachas.
  const rachaVisible = (profile.login_streak ?? 0) > 0;
  $("home-streak-pill").hidden = !rachaVisible;
  $("home-streak").textContent = profile.login_streak;

  const retos = player.todaysChallenges(await challengeCounts());
  const hechos = retos.filter(prog.challengeIsComplete).length;

  $("home-challenge-count").textContent = `${hechos}/${retos.length}`;
  $("home-challenges").innerHTML = retos
    .map((c) => {
      const hecho = prog.challengeIsComplete(c);
      const contador = c.goal > 1 ? `${Math.min(c.progress, c.goal)}/${c.goal}` : "";
      return `<li class="challenge ${hecho ? "is-done" : ""}">
                <span class="challenge-icon" aria-hidden="true">${hecho ? "✅" : prog.challengeIcon(c.kind)}</span>
                <span class="challenge-name">${esc(prog.challengeTitle(c.kind, c.goal))}</span>
                <span class="challenge-count">${hecho ? "" : contador}</span>
              </li>`;
    })
    .join("");

  $("home-challenge-foot").textContent =
    hechos === retos.length
      ? `¡Los tres hechos! +${prog.CHALLENGE_BONUS_XP} XP de bonificación.`
      : `Completa los tres y te llevas +${prog.CHALLENGE_BONUS_XP} XP extra.`;
}

// ── Peso ────────────────────────────────────────────────────────────

$("weight-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const kg = Number($("weight-kg").value);
  if (!kg || kg <= 0) return;

  const entry = await store.insert("weight_entries", {
    date: nowISO(),
    weight_kg: kg,
  });
  $("weight-kg").value = "";
  // Una vez al día: apuntar el peso cinco veces no da cinco premios.
  await awardXP("weightLogged", prog.dedupeKey("weight", new Date(entry.date)));
});

// ── Arranque y sesión ───────────────────────────────────────────────

function showAuth() {
  $("boot").hidden = true;
  $("app").hidden = true;
  $("auth-screen").hidden = false;
}

async function showApp({ local = false } = {}) {
  $("boot").hidden = true;
  $("auth-screen").hidden = true;
  $("app").hidden = false;

  // Lo que no tiene sentido sin cuenta: sincronizar, el correo de la
  // barra lateral, la verificación en dos pasos y el control de
  // registro. Dejarlo a la vista sería ofrecer botones que no hacen
  // nada.
  for (const id of ["refresh", "local-card"]) {
    const el = $(id);
    if (el) el.hidden = id === "local-card" ? !local : local;
  }
  document.querySelectorAll("#view-settings .form-card").forEach((card) => {
    const esSeguridad = card.querySelector("#sec-state, #password-form");
    if (esSeguridad) card.hidden = local;
  });
  $("sign-out").textContent = local ? "Salir" : "Cerrar sesión";
  const salir2 = $("sign-out-2");
  if (salir2) salir2.textContent = local ? "Salir" : "Cerrar sesión";

  const fecha = new Date().toLocaleDateString("es-ES", {
    weekday: "long",
    day: "numeric",
    month: "long",
  });
  $("topbar-date").textContent = fecha.charAt(0).toUpperCase() + fecha.slice(1);

  let email = "";
  if (!local) {
    const { data } = await supabase.auth.getUser();
    email = data?.user?.email ?? "";
  }
  await setDisplayName(email);
  $("side-email").textContent = local ? "Sin cuenta · solo este dispositivo" : email;
  $("side-avatar").textContent = local ? "·" : (email.charAt(0) || "·");

  // Normalmente Inicio; salvo que se venga de pulsar un aviso de rutina.
  let inicial = "home";
  try {
    inicial = sessionStorage.getItem("habitium.vista-inicial") || "home";
    sessionStorage.removeItem("habitium.vista-inicial");
  } catch (e) {}
  go(inicial);       // pinta ya, desde lo que haya en local

  // Primero traer lo que haya en la nube, y SOLO DESPUÉS contar el día.
  //
  // Al revés tiene un fallo serio: en un dispositivo nuevo no hay perfil
  // local, así que registrar el acceso crea uno con racha 1 y fecha de
  // ahora mismo. Ese perfil es "más reciente" que el del móvil, gana la
  // fusión, y la racha de verdad —siete días -- se pierde en los dos
  // sitios. La pantalla ya está pintada, así que esperar aquí no se nota.
  if (!local) await store.sync();

  // El nombre se vuelve a mirar AQUÍ: antes de sincronizar no existe
  // user_settings todavía, así que la primera vez salía el trozo del
  // correo en vez del nombre de verdad.
  await setDisplayName(email);
  if (currentView === "home") $("topbar-title").textContent = greeting();

  try {
    await player.registerDailyLogin();
  } catch (error) {
    console.warn("racha:", error);
  }

  // Si se venía de "crear cuenta y sincronizar", subir lo que había.
  if (!local) await migrarSiTocaba();

  // Los avisos van DESPUÉS del sync: programarlos antes usaría los datos
  // viejos del dispositivo y podría avisar de un paso que ya marcaste
  // desde el móvil hace diez minutos.
  try {
    const estado = await datosDeRutinas();
    avisos.reprogramar(estado);
    await avisos.recuperarPerdido(estado);
  } catch (error) {
    console.warn("avisos:", error);
  }
}

// Pulsar un aviso de rutina trae la app al frente y la lleva a Rutinas
// (ver sw.js). Si la app ya estaba abierta llega por mensaje; si se
// abrió desde cero, por el parámetro de la URL.
navigator.serviceWorker?.addEventListener("message", (e) => {
  if (e.data?.tipo === "ir-a-rutinas") go("routines");
});
try {
  if (new URLSearchParams(location.search).get("vista") === "routines") {
    // Se guarda para después de mostrar la app: go() todavía no puede
    // pintar nada porque la sesión no está comprobada.
    sessionStorage.setItem("habitium.vista-inicial", "routines");
  }
} catch (e) {}

// El desplegable de categorías, desde la única lista que hay.
$("tx-category").innerHTML = Object.entries(CATEGORIES)
  .map(([id, c]) => `<option value="${id}">${c.icon} ${c.name}</option>`)
  .join("");

buildNav();
syncHabitKindFields();
setAuthMode("signin");
renderBackgroundPicker();
updateThemeColor(currentBackground());
applyAccent(currentAccent());

/** La puerta. Tener sesión NO es lo mismo que poder entrar: si la cuenta
 *  tiene verificación en dos pasos, Supabase entrega una sesión a medias
 *  en cuanto la contraseña es correcta, y aquí es donde se corta.
 *
 *  El orden importa: primero se comprueba, y SOLO después se pinta.
 *  Al revés se vería la pantalla de inicio un instante antes de tapar. */
async function continuarSesion() {
  try {
    if (await seg.faltaSegundoFactor(supabase)) return mostrarSegundoPaso();
  } catch (error) {
    console.warn("mfa:", error);
  }
  ocultarSegundoPaso();
  await showApp();
}

supabase.auth.onAuthStateChange((_event, session) => {
  // En modo local, Supabase no manda: un "SIGNED_OUT" suyo (que llega
  // solo por existir el cliente) echaría a la calle a quien entró sin
  // cuenta.
  if (store.esSoloLocal()) return;

  if (session) continuarSesion();
  else {
    ocultarSegundoPaso();
    showAuth();
    setAuthMessage("");
  }
});

// En un dispositivo prestado —el iPad del instituto— la sesión se cierra
// sola a los veinte minutos sin tocar nada. En el tuyo no, claro.
if (dispositivoAjeno) {
  seg.vigilarInactividad(20, async () => {
    await doSignOut();
    setAuthMessage("Sesión cerrada por seguridad: llevabas un rato sin usarla.");
  });
}

// El modo sin cuenta manda: quien lo eligió no debería ver la pantalla
// de login nunca más, ni esperar a que Supabase conteste para entrar.
if (enModoLocal()) {
  store.configureLocal();
  showApp({ local: true });
} else {
  // Sesión inicial: onAuthStateChange también dispara al arrancar, pero
  // comprobarlo aquí evita el parpadeo de la pantalla de carga.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (session) continuarSesion();
  else showAuth();
}
