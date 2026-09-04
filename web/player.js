// player.js — concede experiencia, lleva la racha y desbloquea premios.
//
// Es el equivalente de ProgressionRepository.swift, y con las mismas
// tres reglas que sostienen todo el sistema:
//
//   1. Nada se premia dos veces. Cada concesión lleva una clave única
//      ("habit:<id>:2026-09-03"); si ya existe, no se da nada. Sin esto,
//      marcar y desmarcar un hábito sería una máquina de XP infinita.
//   2. Solo se premia lo que suma. Desmarcar no resta: castigar un error
//      de pulsación haría que la gente evitara tocar la app, que es lo
//      contrario de lo que se busca.
//   3. La racha se mide en días naturales locales, no en horas. Entrar a
//      las 23:50 y otra vez a las 00:10 son dos días seguidos.
//
// ── Por qué el total se recalcula desde los eventos ──────────────────
//
// `player_profiles` es una fila única por usuario y se sincroniza con
// "gana el más reciente". Eso, para un CONTADOR, tiene un fallo: si
// ganas XP en el móvil y luego la web sube un perfil suyo más nuevo, el
// contador del móvil se pierde entero.
//
// Los eventos (`xp_events`) no tienen ese problema: son filas
// independientes, cada una con su clave única en Postgres, así que dos
// dispositivos nunca pueden duplicar ni pisarse el mismo premio. Por eso
// aquí el total se RECALCULA sumando los eventos (`reconcile`) en vez de
// confiar en el número guardado. El número se sigue escribiendo para que
// el iPhone lo lea como siempre, pero la verdad son los eventos.

import * as store from "./store.js";
import * as p from "./progression.js";

const TABLE = "player_profiles";
const EVENTS = "xp_events";

// ── Avisos a la interfaz ────────────────────────────────────────────
//
// Se avisa desde aquí, el único punto por el que pasa toda concesión, en
// vez de desde cada sitio que premia algo: así una fuente nueva de XP no
// puede olvidarse de avisar.

const listeners = new Set();
export function onAward(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
function emit(award) {
  for (const fn of listeners) fn(award);
}

// ── Una cosa cada vez ───────────────────────────────────────────────
//
// Conceder XP es leer-comprobar-escribir, y eso no aguanta que dos
// llamadas se solapen: las dos leen "aún no está premiado", las dos
// escriben, y se premia dos veces lo mismo.
//
// No es hipotético. Al arrancar, la web llama a showApp() DOS veces (una
// por onAuthStateChange y otra por getSession, que es como funciona
// Supabase), así que el premio por entrar del día se concedía por
// duplicado: 20 XP en vez de 10. Se detectó ejecutando la web de verdad
// en un navegador con un doble de Supabase.
//
// Con esto, cada operación espera a que termine la anterior. Son
// milisegundos y ocurren en respuesta a un toque, así que no se nota.

let cola = Promise.resolve();

function enSerie(fn) {
  const resultado = cola.then(fn, fn);
  // La cola sigue viva aunque una operación falle: un error al premiar
  // un hábito no puede dejar el sistema de XP bloqueado para siempre.
  cola = resultado.then(
    () => undefined,
    () => undefined
  );
  return resultado;
}

// ── Utilidades de fecha ─────────────────────────────────────────────

const startOfDay = (date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());

/** Días naturales entre dos comienzos de día.
 *  Con `round` y no `floor` a propósito: los días de cambio de hora
 *  duran 23 o 25 horas, y un `floor` convertiría el de 23 en "0 días"
 *  rompiendo la racha de quien no ha fallado ni un día. */
const daysBetween = (from, to) => Math.round((to - from) / 86400000);

// ── Perfil ──────────────────────────────────────────────────────────

const EMPTY_PROFILE = {
  total_xp: 0,
  login_streak: 0,
  longest_login_streak: 0,
  last_login_date: null,
  season_id: "",
  season_xp: 0,
  unlocked_reward_ids: [],
};

/** El perfil del usuario, creándolo la primera vez y pasando de
 *  temporada si ha cambiado el mes. */
export async function profile() {
  let row = await store.getSingleton(TABLE);
  if (!row) {
    row = await store.putSingleton(TABLE, { ...EMPTY_PROFILE, season_id: p.currentSeasonID() });
  }

  // Al entrar en un mes nuevo la experiencia de temporada vuelve a cero.
  // Lo ya desbloqueado se conserva a propósito: quitarlo castigaría por
  // descansar un mes, que es justo lo contrario de lo que se busca.
  const season = p.currentSeasonID();
  if (row.season_id !== season) {
    row = await store.putSingleton(TABLE, { season_id: season, season_xp: 0 });
  }

  return { ...EMPTY_PROFILE, ...row, unlocked_reward_ids: row.unlocked_reward_ids ?? [] };
}

/** Vuelve a sumar el total y el de temporada desde los eventos, que son
 *  la fuente de verdad (ver la cabecera). Barato: son decenas de filas.
 *  Solo escribe si algo ha cambiado, o se dispararía una cadena infinita
 *  de escritura → sincronización → escritura. */
async function reconcileAhora() {
  const events = await store.all(EVENTS);
  const season = p.currentSeasonID();

  const total = events.reduce((sum, e) => sum + (e.amount ?? 0), 0);
  const seasonTotal = events
    .filter((e) => e.date && p.currentSeasonID(new Date(e.date)) === season)
    .reduce((sum, e) => sum + (e.amount ?? 0), 0);

  const prof = await profile();
  const unlocked = [
    ...new Set([...prof.unlocked_reward_ids, ...p.unlockedTiers(seasonTotal).map((t) => t.id)]),
  ];

  const cambia =
    prof.total_xp !== total ||
    prof.season_xp !== seasonTotal ||
    unlocked.length !== prof.unlocked_reward_ids.length;

  if (!cambia) return prof;

  await store.putSingleton(TABLE, {
    total_xp: total,
    season_xp: seasonTotal,
    unlocked_reward_ids: unlocked,
    season_id: season,
  });
  // Se relee con profile() y no se devuelve lo que escupe putSingleton
  // para que salga siempre con los mismos valores por defecto aplicados.
  return profile();
}

// ── Conceder experiencia ────────────────────────────────────────────

/** Concede experiencia si esa clave no se había premiado ya.
 *  Devuelve null cuando no se concedió nada (repetido). */
async function awardAhora(source, key, date = new Date()) {
  const events = await store.all(EVENTS);
  if (events.some((e) => e.dedupe_key === key)) return null;

  const prof = await profile();
  const levelBefore = p.levelForTotalXP(prof.total_xp);
  const tiersBefore = new Set(p.unlockedTiers(prof.season_xp).map((t) => t.id));

  const amount = p.xpFor(source);
  if (amount <= 0) return null;

  await store.insert(EVENTS, {
    source,
    amount,
    date: date.toISOString(),
    dedupe_key: key,
  });

  const totalXP = prof.total_xp + amount;
  const seasonXP = prof.season_xp + amount;
  const newTierIDs = p
    .unlockedTiers(seasonXP)
    .map((t) => t.id)
    .filter((id) => !tiersBefore.has(id));

  await store.putSingleton(TABLE, {
    total_xp: totalXP,
    season_xp: seasonXP,
    unlocked_reward_ids: [...new Set([...prof.unlocked_reward_ids, ...newTierIDs])],
  });

  // `result` y no `award`: una constante con el nombre de la función
  // taparía a la propia función dentro de este bloque.
  const result = {
    source,
    amount,
    didLevelUp: p.levelForTotalXP(totalXP) > levelBefore,
    newLevel: p.levelForTotalXP(totalXP),
    unlockedTiers: newTierIDs,
  };
  emit(result);
  return result;
}

/** Registra el acceso del día: actualiza la racha y premia por entrar. */
async function registerDailyLoginAhora(date = new Date()) {
  const prof = await profile();
  const today = startOfDay(date);

  let streak;
  if (prof.last_login_date) {
    const last = startOfDay(new Date(prof.last_login_date));
    if (last.getTime() === today.getTime()) return null; // ya contado hoy
    // Exactamente un día = sigue la racha. Más de uno = se rompió y
    // vuelve a empezar en 1 (hoy cuenta como el primer día).
    streak = daysBetween(last, today) === 1 ? (prof.login_streak ?? 0) + 1 : 1;
  } else {
    streak = 1;
  }

  await store.putSingleton(TABLE, {
    login_streak: streak,
    longest_login_streak: Math.max(prof.longest_login_streak ?? 0, streak),
    last_login_date: today.toISOString(),
  });

  const loginAward = await awardAhora("dailyLogin", p.dedupeKey("login", today), date);

  // Un hito de racha se premia aparte, para que además del XP haya un
  // momento reconocible ("¡7 días seguidos!").
  if (p.isStreakMilestone(streak)) {
    const milestone = await awardAhora("streakMilestone", p.dedupeKey(`streak-${streak}`, today), date);
    // Si se concedieron los dos, se devuelve el del hito: es el que
    // merece celebrarse en pantalla.
    if (milestone) return milestone;
  }

  return loginAward;
}


// ── Lo que usa el resto de la app ───────────────────────────────────
//
// Las tres operaciones que escriben van por la cola. Las de solo
// lectura (profile, recentEvents, dailyXP) no hacen falta: leer de más
// no rompe nada.

/** Concede experiencia si esa clave no se había premiado ya.
 *  Devuelve null cuando no se concedió nada (repetido). */
export const award = (source, key, date = new Date()) =>
  enSerie(() => awardAhora(source, key, date));

/** Registra el acceso del día: actualiza la racha y premia por entrar. */
export const registerDailyLogin = (date = new Date()) =>
  enSerie(() => registerDailyLoginAhora(date));

/** Recalcula el total desde los eventos. */
export const reconcile = () => enSerie(reconcileAhora);

// ── Historial ───────────────────────────────────────────────────────

/** Últimos eventos, del más reciente al más antiguo. */
export async function recentEvents(limit = 12) {
  const events = await store.all(EVENTS);
  return events.sort((a, b) => new Date(b.date) - new Date(a.date)).slice(0, limit);
}

/** XP de cada uno de los últimos `days` días, del más antiguo al más
 *  reciente — para el gráfico de la semana. */
export async function dailyXP(days = 7) {
  const events = await store.all(EVENTS);
  const today = startOfDay(new Date());
  const totals = new Map();

  for (const event of events) {
    if (!event.date) continue;
    const day = startOfDay(new Date(event.date)).getTime();
    totals.set(day, (totals.get(day) ?? 0) + (event.amount ?? 0));
  }

  const out = [];
  for (let offset = days - 1; offset >= 0; offset--) {
    const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
    out.push({ date: day, xp: totals.get(day.getTime()) ?? 0 });
  }
  return out;
}

// ── Retos del día ───────────────────────────────────────────────────

/** Los tres retos de hoy con su progreso.
 *
 *  El progreso NO se guarda: se calcula mirando lo que ya hay (hábitos
 *  cumplidos hoy, tareas completadas hoy…). Un contador aparte sería una
 *  segunda fuente de verdad que se desincronizaría en cuanto alguien
 *  borrase una comida.
 *
 *  `counts` lo trae app.js, que es quien tiene los datos del día a mano.
 */
export function todaysChallenges(counts, date = new Date()) {
  return p.dailyChallenges(date).map((challenge) => ({
    ...challenge,
    progress: counts[challenge.kind] ?? 0,
  }));
}

/** Concede la bonificación si están los tres. La clave lleva el día, así
 *  que solo se cobra una vez. */
export async function awardBonusIfComplete(counts, date = new Date()) {
  const challenges = todaysChallenges(counts, date);
  if (!challenges.length || !challenges.every(p.challengeIsComplete)) return null;
  return award("dailyChallenge", p.dedupeKey("challenges", date), date);
}
