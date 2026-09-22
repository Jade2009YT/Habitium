// Habitium — avisos en el navegador.
//
// ── Lo primero, la verdad incómoda ──────────────────────────────────
//
// Una página web NO puede programar una notificación para dentro de tres
// horas y desentenderse. En el iPhone eso lo hace el sistema
// (UNUserNotificationCenter) y funciona con la app cerrada. Aquí no
// existe equivalente que se pueda usar hoy:
//
//   · La API de "Notification Triggers", que era exactamente eso, se
//     probó en Chrome y se retiró. No está en ningún navegador.
//   · Las notificaciones push SÍ funcionan con la app cerrada, pero
//     necesitan un servidor propio que las empuje (claves VAPID, un
//     proceso escuchando). Supabase solo no basta, y montar eso es otro
//     proyecto.
//
// Así que esto hace lo máximo que se puede hacer sin servidor, y lo dice
// en la propia pantalla en vez de disimularlo:
//
//   1. Mientras la app está abierta (o instalada en la pantalla de
//      inicio y abierta de fondo), los avisos saltan a su hora. Es el
//      caso real de una rutina de mañana: el móvil está encima de la
//      mesilla y la app abierta de anoche.
//   2. Al abrir la app, si te has perdido un aviso hace poco, se te
//      recuerda una vez. Enterarte cinco minutos tarde sigue valiendo.
//   3. Si cierras la pestaña del todo, no hay aviso. Punto.
//
// En el iPhone, la app nativa usa notificaciones de verdad y nada de
// esto le afecta.

import * as rutinas from "./routines.js";

/** Cuánto tiempo después de su hora sigue teniendo sentido avisar. Diez
 *  minutos: pasado eso ya te has duchado o ya no vas a hacerlo. */
const MARGEN_ATRASO_MIN = 10;

/** Los avisos ya dados hoy, para no repetirlos al recargar la página.
 *  Va en localStorage porque es información de ESTE dispositivo: que el
 *  móvil te avisara no significa que el portátil no deba hacerlo. */
const CLAVE_DADOS = "habitium.avisos.dados";

function dados() {
  try {
    const datos = JSON.parse(localStorage.getItem(CLAVE_DADOS) ?? "{}") || {};
    // Se tira lo que no sea de hoy: si no, el objeto crecería para siempre.
    const hoy = rutinas.claveDia(new Date());
    return datos.dia === hoy ? new Set(datos.ids ?? []) : new Set();
  } catch (e) {
    return new Set();
  }
}

function apuntarDado(id) {
  try {
    const set = dados();
    set.add(id);
    localStorage.setItem(CLAVE_DADOS, JSON.stringify({
      dia: rutinas.claveDia(new Date()),
      ids: [...set],
    }));
  } catch (e) {
    /* modo incógnito: se repetirá algún aviso, no es grave */
  }
}

// ── Permiso ─────────────────────────────────────────────────────────

export function soportadas() {
  return typeof Notification !== "undefined";
}

export function estadoPermiso() {
  if (!soportadas()) return "no-soportado";
  return Notification.permission;   // "granted" | "denied" | "default"
}

/** Pedir permiso. Solo se llama desde un clic del usuario: los
 *  navegadores rechazan (y algunos penalizan) la petición automática al
 *  cargar, y además es de mala educación. */
export async function pedirPermiso() {
  if (!soportadas()) return "no-soportado";
  if (Notification.permission !== "default") return Notification.permission;
  try {
    return await Notification.requestPermission();
  } catch (e) {
    return "denied";
  }
}

// ── Mostrar ─────────────────────────────────────────────────────────

/** Se muestra a través del service worker cuando se puede.
 *
 *  Por qué no `new Notification(...)` a secas: en Android, Chrome
 *  directamente NO lo permite si hay un service worker registrado —
 *  lanza una excepción. Y a través del worker la notificación sobrevive
 *  aunque la pestaña se cierre justo después, y se puede pulsar para
 *  volver a la app. */
async function mostrar(titulo, opciones) {
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg?.showNotification) {
      await reg.showNotification(titulo, opciones);
      return true;
    }
  } catch (e) {
    /* se intenta por el otro camino */
  }
  try {
    new Notification(titulo, opciones);
    return true;
  } catch (e) {
    return false;
  }
}

function opcionesDe(aviso) {
  return {
    body: aviso.cuerpo,
    tag: aviso.id,              // reemplaza el anterior del mismo paso
    renotify: false,
    icon: "./icon.png",
    badge: "./icon.png",
    // Vibración corta: se nota en el bolsillo sin ser una alarma.
    vibrate: [80, 40, 80],
    data: { routineId: aviso.routineId, stepId: aviso.stepId },
  };
}

// ── El planificador ─────────────────────────────────────────────────

let temporizadores = [];

function limpiarTemporizadores() {
  for (const t of temporizadores) clearTimeout(t);
  temporizadores = [];
}

/**
 * Reprograma TODO desde cero a partir del estado actual.
 *
 * Se llama al arrancar, al marcar un paso y al editar una rutina. Es a
 * propósito que rehaga todo en vez de ir tocando lo que cambió: el
 * horario se recalcula en cascada (marcar un paso mueve todos los
 * siguientes), así que un recálculo entero es más simple Y más correcto
 * que intentar adivinar qué avisos siguen valiendo.
 *
 * `setTimeout` con más de 24.8 días se desborda y dispara al instante,
 * pero aquí nunca se programa más allá del final del día, así que no
 * puede pasar.
 */
export function reprogramar({ routines, steps, logs }, ahora = new Date()) {
  limpiarTemporizadores();
  if (estadoPermiso() !== "granted") return 0;

  const pendientes = rutinas.todosLosAvisos(routines, steps, logs, ahora);
  const yaDados = dados();
  let puestos = 0;

  for (const aviso of pendientes) {
    if (yaDados.has(aviso.id)) continue;
    const espera = aviso.cuando - ahora;
    if (espera < 0) continue;

    temporizadores.push(setTimeout(() => {
      // Se vuelve a comprobar al disparar: en el rato de espera el paso
      // puede haberse marcado desde el móvil, y avisar entonces sería
      // justo lo que hace que la gente quite los permisos.
      if (dados().has(aviso.id)) return;
      apuntarDado(aviso.id);
      mostrar(aviso.titulo, opcionesDe(aviso));
    }, espera));
    puestos++;
  }
  return puestos;
}

/**
 * Al abrir la app: ¿me he perdido algo hace poco?
 *
 * Solo el MÁS RECIENTE, y solo si se pasó hace menos de diez minutos.
 * Soltar cuatro notificaciones de golpe al abrir la app por la tarde es
 * la forma más rápida de que alguien las desactive para siempre.
 */
export async function recuperarPerdido({ routines, steps, logs }, ahora = new Date()) {
  if (estadoPermiso() !== "granted") return null;

  const yaDados = dados();
  const perdidos = rutinas
    .todosLosAvisos(routines, steps, logs, ahora, MARGEN_ATRASO_MIN)
    .filter((a) => a.cuando <= ahora && !yaDados.has(a.id));

  const ultimo = perdidos.at(-1);
  if (!ultimo) return null;

  // Los anteriores se dan por vistos sin enseñarlos: ya no sirven, pero
  // marcarlos evita que vuelvan a salir en la siguiente recarga.
  for (const a of perdidos) apuntarDado(a.id);

  await mostrar(ultimo.titulo, {
    ...opcionesDe(ultimo),
    body: `${ultimo.cuerpo} (se te pasó hace un momento)`,
  });
  return ultimo;
}

/** Un aviso de prueba, para que se vea que funciona antes de fiarse.
 *  Sin esto, la gente activa los permisos y se queda con la duda hasta
 *  la mañana siguiente. */
export async function avisoDePrueba() {
  return mostrar("🔔 Habitium", {
    body: "Perfecto, así se van a ver tus rutinas.",
    tag: "habitium-prueba",
    icon: "./icon.png",
  });
}

/** Texto honesto sobre qué va a pasar de verdad en este dispositivo. */
export function explicacion() {
  if (!soportadas()) {
    return "Este navegador no sabe enseñar notificaciones. En el iPhone, añade Habitium a la pantalla de inicio.";
  }
  switch (Notification.permission) {
    case "granted":
      return "Activadas. Los avisos saltan mientras Habitium esté abierta — aunque sea de fondo. Si cierras la app del todo, no.";
    case "denied":
      return "Bloqueadas. Hay que reactivarlas desde los ajustes del navegador: Habitium ya no puede volver a preguntar.";
    default:
      return "Sin activar. Habitium te avisará de cada paso de tus rutinas a su hora.";
  }
}
