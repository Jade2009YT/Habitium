// progression.js — niveles, racha, retos del día y pase de temporada.
//
// Es el gemelo en JavaScript de tres archivos de iOS:
//   · ProgressionEngine.swift  → la curva de niveles
//   · SeasonPass.swift         → los 12 niveles del pase
//   · DailyChallenges.swift    → los tres retos que cambian cada día
//
// Están duplicados porque no hay forma de compartir código entre Swift y
// el navegador, pero tienen que dar EXACTAMENTE lo mismo: el nivel que
// ves en el iPhone y en la web salen del mismo total de XP, y los retos
// del día tienen que ser los tres mismos en los dos sitios el mismo día.
//
// Lo delicado es esto último. Los retos se sortean con un generador
// sembrado con la fecha, así que para que iPhone y web coincidan hay que
// reproducir el sorteo de Swift al detalle — incluido un detalle que es
// fácil pasar por alto y que rompería todo en silencio: cuando solo hay
// una opción posible, Swift IGUAL consume un número del generador. Si
// aquí nos saltásemos esa tirada (que es lo natural: "solo hay una
// opción, devuelvo esa"), a partir de ese punto las dos secuencias
// divergirían y cada dispositivo mostraría retos distintos.
//
// Este archivo no toca el DOM ni la base de datos a propósito: así se
// puede probar solo, con node (ver web/progression.test.mjs).

// ── Curva de niveles ────────────────────────────────────────────────
//
// Cada nivel cuesta 100 + (nivel-1)*50. Con un uso normal salen unos
// 100-150 XP al día: un nivel diario al principio, y cada pocos días más
// adelante. Una curva exponencial se atasca; una plana deja de premiar.

export function xpToAdvance(fromLevel) {
  return Math.max(1, 100 + (fromLevel - 1) * 50);
}

/** XP total acumulado para alcanzar un nivel. El 1 es el inicial: 0. */
export function totalXPRequired(forLevel) {
  if (forLevel <= 1) return 0;
  let sum = 0;
  for (let l = 1; l < forLevel; l++) sum += xpToAdvance(l);
  return sum;
}

export function levelForTotalXP(xp) {
  if (xp <= 0) return 1;
  let level = 1;
  let remaining = xp;
  while (remaining >= xpToAdvance(level)) {
    remaining -= xpToAdvance(level);
    level++;
  }
  return level;
}

/** Progreso dentro del nivel actual, de 0 a 1 — para la barra. */
export function progressWithinLevel(totalXP) {
  const level = levelForTotalXP(totalXP);
  const earned = totalXP - totalXPRequired(level);
  const needed = xpToAdvance(level);
  return needed > 0 ? Math.min(Math.max(earned / needed, 0), 1) : 0;
}

export function xpRemainingToNextLevel(totalXP) {
  const level = levelForTotalXP(totalXP);
  const earned = totalXP - totalXPRequired(level);
  return Math.max(0, xpToAdvance(level) - earned);
}

/** Un nombre además del número: "Nivel 12" dice menos que "Constante". */
export function titleForLevel(level) {
  if (level < 3) return "Empezando";
  if (level < 6) return "Cogiendo ritmo";
  if (level < 10) return "Constante";
  if (level < 15) return "En racha";
  if (level < 25) return "Imparable";
  if (level < 40) return "Referente";
  return "Leyenda";
}

/** Hitos de racha con XP extra, espaciados para que siempre haya uno
 *  cerca sin que lleguen a ser rutina. */
export const STREAK_MILESTONES = [3, 7, 14, 30, 60, 100, 180, 365];
export const isStreakMilestone = (days) => STREAK_MILESTONES.includes(days);

// ── De dónde sale la experiencia ────────────────────────────────────
//
// Calibrado para que mande el esfuerzo sobre el relleno: registrar una
// comida da poco, cerrar TODOS los hábitos del día da mucho. Si diera lo
// mismo, lo óptimo sería registrar veinte comidas y no cumplir nada.
//
// Las claves son las mismas cadenas que el enum XPSource de Swift,
// porque acaban guardadas en la misma columna de Postgres.

export const XP_SOURCES = {
  dailyLogin: { xp: 10, name: "Entrar cada día", icon: "☀️" },
  habitCompleted: { xp: 15, name: "Hábito cumplido", icon: "🔁" },
  allHabitsCompleted: { xp: 40, name: "Todos los hábitos del día", icon: "🏆" },
  mealLogged: { xp: 5, name: "Comida registrada", icon: "🍽️" },
  taskCompleted: { xp: 10, name: "Tarea completada", icon: "✅" },
  focusTaskCompleted: { xp: 20, name: "Foco del día completado", icon: "⭐" },
  medicationTaken: { xp: 10, name: "Medicación tomada", icon: "💊" },
  workoutLogged: { xp: 30, name: "Entrenamiento registrado", icon: "🏋️" },
  weightLogged: { xp: 5, name: "Peso registrado", icon: "⚖️" },
  streakMilestone: { xp: 50, name: "Hito de racha", icon: "🔥" },
  dailyChallenge: { xp: 60, name: "Retos del día completados", icon: "🎯" },
};

export const xpFor = (source) => XP_SOURCES[source]?.xp ?? 0;

// ── Pase de temporada ───────────────────────────────────────────────
//
// Las recompensas son cosméticas y eso es deliberado: un pase que
// desbloquease funciones dejaría la app peor para quien no juegue, y
// esto es cuidado personal, no un juego con micropagos.
//
// Los primeros niveles están muy juntos a propósito. Desbloquear algo el
// primer día es lo que engancha; si la primera recompensa tardara una
// semana, casi nadie llegaría a verla.

export const ACCENTS = {
  classic: { name: "Clásico", color: "#15a34a" },
  ocean: { name: "Océano", color: "#0d8cc7" },
  sunset: { name: "Atardecer", color: "#f26b3d" },
  forest: { name: "Bosque", color: "#2e7347" },
  grape: { name: "Uva", color: "#8c3db3" },
  midnight: { name: "Medianoche", color: "#384273" },
};

export const SEASON_TIERS = [
  { id: "t1", tier: 1, xpRequired: 50, kind: "badge", value: "Primer paso", icon: "🌱" },
  { id: "t2", tier: 2, xpRequired: 150, kind: "accent", value: "ocean", icon: "🎨" },
  { id: "t3", tier: 3, xpRequired: 300, kind: "title", value: "Constante", icon: "🏅" },
  { id: "t4", tier: 4, xpRequired: 500, kind: "badge", value: "En racha", icon: "🔥" },
  { id: "t5", tier: 5, xpRequired: 750, kind: "accent", value: "sunset", icon: "🎨" },
  { id: "t6", tier: 6, xpRequired: 1050, kind: "title", value: "Disciplinado", icon: "🏅" },
  { id: "t7", tier: 7, xpRequired: 1400, kind: "badge", value: "Imparable", icon: "⚡" },
  { id: "t8", tier: 8, xpRequired: 1800, kind: "accent", value: "forest", icon: "🎨" },
  { id: "t9", tier: 9, xpRequired: 2250, kind: "title", value: "Referente", icon: "🏅" },
  { id: "t10", tier: 10, xpRequired: 2750, kind: "accent", value: "grape", icon: "🎨" },
  { id: "t11", tier: 11, xpRequired: 3300, kind: "badge", value: "Corona del mes", icon: "👑" },
  { id: "t12", tier: 12, xpRequired: 4000, kind: "accent", value: "midnight", icon: "🎨" },
];

export function tierRewardName(tier) {
  if (tier.kind === "accent") return `Tema ${ACCENTS[tier.value]?.name ?? tier.value}`;
  if (tier.kind === "title") return `Título «${tier.value}»`;
  return tier.value;
}

export const unlockedTiers = (seasonXP) => SEASON_TIERS.filter((t) => seasonXP >= t.xpRequired);
export const nextTier = (seasonXP) => SEASON_TIERS.find((t) => seasonXP < t.xpRequired) ?? null;
export const seasonMaxXP = SEASON_TIERS[SEASON_TIERS.length - 1].xpRequired;

export function progressToNextTier(seasonXP) {
  const next = nextTier(seasonXP);
  if (!next) return 1;
  const reached = SEASON_TIERS.filter((t) => seasonXP >= t.xpRequired);
  const previous = reached.length ? reached[reached.length - 1].xpRequired : 0;
  const span = next.xpRequired - previous;
  return span > 0 ? Math.min(Math.max((seasonXP - previous) / span, 0), 1) : 1;
}

/** Los acentos que este perfil puede usar. El clásico siempre está. */
export function availableAccents(unlockedRewardIDs = []) {
  const ids = new Set(unlockedRewardIDs);
  const accents = ["classic"];
  for (const tier of SEASON_TIERS) {
    if (tier.kind === "accent" && ids.has(tier.id)) accents.push(tier.value);
  }
  return accents;
}

/** El título más alto desbloqueado, si hay alguno. */
export function highestTitle(unlockedRewardIDs = []) {
  const ids = new Set(unlockedRewardIDs);
  let result = null;
  for (const tier of SEASON_TIERS) {
    if (tier.kind === "title" && ids.has(tier.id)) result = tier.value;
  }
  return result;
}

/** "2026-09" — la temporada es el mes natural LOCAL, no en UTC: debe
 *  cambiar cuando cambia el mes para quien usa la app. */
export function currentSeasonID(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

/** "habit:<id>:2026-09-03" — el formato de clave anti-repetición, igual
 *  que SwiftDataProgressionRepository.key. */
export function dedupeKey(prefix, date = new Date()) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${prefix}:${y}-${m}-${d}`;
}

// ── Generador reproducible (SplitMix64) ─────────────────────────────
//
// Copia exacta de SeededGenerator en Swift. Va con BigInt porque hace
// falta aritmética de 64 bits sin signo con desbordamiento envolvente, y
// los números normales de JavaScript solo dan 53 bits enteros exactos:
// con ellos la secuencia se desviaría de la del iPhone al primer
// desbordamiento.

const M64 = (1n << 64n) - 1n;

export class SeededGenerator {
  constructor(seed) {
    // El +1 evita el caso degenerado de semilla 0, igual que en Swift.
    this.state = (BigInt(seed) + 1n) & M64;
  }

  next() {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & M64;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & M64;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & M64;
    return (z ^ (z >> 31n)) & M64;
  }

  /// Equivalente a `Int.random(in: 0..<bound, using:)` de Swift, que por
  /// dentro llama a `next(upperBound:)`.
  ///
  /// OJO con `bound === 1`: la tentación es devolver 0 sin más, pero
  /// Swift hace `tmp = (max % 1) + 1 = 1`, luego `range = 0`, y su bucle
  /// es un `repeat…while`, así que TIRA UNA VEZ igualmente y devuelve
  /// `r % 1 = 0`. Aquí pasa lo mismo por construcción: no hay atajo para
  /// bound 1. Si lo hubiera, los retos con una sola opción de objetivo
  /// (peso, entrenar, foco) desincronizarían el resto del sorteo y la
  /// web mostraría retos distintos a los del iPhone.
  nextBelow(bound) {
    const n = BigInt(bound);
    if (n <= 0n) throw new RangeError("nextBelow necesita un límite positivo");
    const tmp = (M64 % n) + 1n;
    const range = tmp === n ? 0n : tmp;
    let r = this.next();
    while (r < range) r = this.next();
    return Number(r % n);
  }
}

// ── Retos del día ───────────────────────────────────────────────────
//
// Nivel y racha premian seguir haciendo lo de siempre: eso mantiene,
// pero no sorprende. Los retos cambian el objetivo cada mañana, así que
// abrir la app tiene algo nuevo aunque tus hábitos sean los de siempre.

export const CHALLENGE_KINDS = ["habits", "tasks", "meals", "medication", "weight", "workout", "focus"];

const GOAL_OPTIONS = {
  habits: [2, 3, 4],
  tasks: [1, 2, 3],
  meals: [2, 3],
  medication: [1],
  weight: [1],
  workout: [1],
  focus: [1],
};

const CHALLENGE_ICONS = {
  habits: "🔁",
  tasks: "✅",
  meals: "🍽️",
  medication: "💊",
  weight: "⚖️",
  workout: "🏋️",
  focus: "⭐",
};

export function challengeTitle(kind, goal) {
  switch (kind) {
    case "habits": return goal === 1 ? "Cumple 1 hábito" : `Cumple ${goal} hábitos`;
    case "tasks": return goal === 1 ? "Completa 1 tarea" : `Completa ${goal} tareas`;
    case "meals": return `Registra ${goal} comidas`;
    case "medication": return "Toma toda tu medicación";
    case "weight": return "Registra tu peso";
    case "workout": return "Entrena hoy";
    case "focus": return "Cierra un foco del día";
    default: return kind;
  }
}

export const challengeIcon = (kind) => CHALLENGE_ICONS[kind] ?? "🎯";

/** Número estable a partir del día natural local: 20260903. */
export function daySeed(date = new Date()) {
  const value = date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate();
  return Math.max(0, value);
}

/** Los tres retos del día, sin progreso todavía. */
export function dailyChallenges(date = new Date()) {
  const g = new SeededGenerator(daySeed(date));

  // Medicación y entrenamiento solo aparecen a veces: pedirlos a diario
  // a quien no toma nada ni entrena sería un reto imposible permanente,
  // que desmotiva más que no tener retos.
  const pool = CHALLENGE_KINDS.filter((k) => k !== "medication" && k !== "workout");
  if (g.nextBelow(3) === 0) pool.push("medication");
  if (g.nextBelow(3) === 0) pool.push("workout");

  const chosen = [];
  while (chosen.length < 3 && pool.length > 0) {
    chosen.push(pool.splice(g.nextBelow(pool.length), 1)[0]);
  }

  return chosen.map((kind) => {
    const options = GOAL_OPTIONS[kind];
    return { kind, goal: options[g.nextBelow(options.length)], progress: 0 };
  });
}

export const challengeFraction = (c) => (c.goal > 0 ? Math.min(c.progress / c.goal, 1) : 0);
export const challengeIsComplete = (c) => c.progress >= c.goal;

/** Bonificación por completar los tres. */
export const CHALLENGE_BONUS_XP = XP_SOURCES.dailyChallenge.xp;
