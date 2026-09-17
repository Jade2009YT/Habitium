// study.js — las cuentas del módulo de Estudios.
//
// Sin DOM y sin base de datos a propósito, igual que progression.js: así
// se puede probar solo (web/study.test.mjs). Aquí están las dos cuentas
// que la gente hace mal a mano y por las que acaba montándose una hoja
// de cálculo: la media ponderada y el porcentaje de asistencia.

// ── Media ponderada ─────────────────────────────────────────────────

/** La media de una asignatura a partir de sus notas.
 *
 *  Dos reglas que no son obvias y que cambian el resultado:
 *
 *  1. Solo entran las notas marcadas como "cuenta para la media". Un
 *     parcial pendiente de recuperar o un trabajo sin corregir están
 *     ahí para no perderlos de vista, pero meterlos en la media daría
 *     un número falso.
 *  2. Se divide entre el peso REALMENTE contado, no entre 100. A mitad
 *     de curso solo has hecho el 45 % de la nota; dividir entre 100
 *     diría que llevas un 3,2 cuando en realidad llevas un 7,1 de lo
 *     evaluado hasta ahora. Es la diferencia entre "voy bien" y
 *     "estoy suspendiendo", y es el error clásico de la hoja de cálculo.
 */
export function weightedAverage(grades) {
  const cuentan = grades.filter((g) => g.counts_for_average && Number(g.weight) > 0);
  const pesoTotal = cuentan.reduce((s, g) => s + Number(g.weight), 0);
  if (pesoTotal <= 0) return null;
  const suma = cuentan.reduce((s, g) => s + Number(g.score) * Number(g.weight), 0);
  return suma / pesoTotal;
}

/** Cuánto del curso está ya evaluado, de 0 a 1. */
export function weightCovered(grades) {
  const total = grades
    .filter((g) => g.counts_for_average)
    .reduce((s, g) => s + Number(g.weight), 0);
  return Math.min(Math.max(total / 100, 0), 1);
}

/** La nota ponderada de una prueba: lo que aporta a la nota final. */
export const weightedPoints = (grade) =>
  grade.counts_for_average ? (Number(grade.score) * Number(grade.weight)) / 100 : 0;

/** Lo que llevas acumulado sobre la nota final (no sobre lo evaluado). */
export const pointsSoFar = (grades) => grades.reduce((s, g) => s + weightedPoints(g), 0);

/** Qué nota necesitas en lo que queda para llegar a `objetivo`.
 *
 *  Devuelve null si ya no queda nada por evaluar. Puede dar más de 10 —
 *  y es información útil: significa que ya no llegas, y es mejor saberlo
 *  con tiempo que enterarte en junio. */
export function neededInRemaining(grades, objetivo = 5) {
  const pesoRestante = 100 - grades.filter((g) => g.counts_for_average).reduce((s, g) => s + Number(g.weight), 0);
  if (pesoRestante <= 0.001) return null;
  return ((objetivo - pointsSoFar(grades)) * 100) / pesoRestante;
}

// ── Asistencia ──────────────────────────────────────────────────────

/** Porcentaje de asistencia, de 0 a 100. */
export function attendance(subject) {
  const total = Number(subject.total_classes) || 0;
  if (total <= 0) return null;
  const faltadas = Math.min(Number(subject.hours_missed) || 0, total);
  return ((total - faltadas) / total) * 100;
}

/** Cuántas horas te quedan por faltar antes de pasarte del máximo.
 *  Negativo significa que ya te has pasado. */
export function absencesLeft(subject) {
  const max = Number(subject.max_absences) || 0;
  if (max <= 0) return null;
  return max - (Number(subject.hours_missed) || 0);
}

// ── Estado de una asignatura ────────────────────────────────────────

export const PASS_MARK = 5;

/** Un veredicto corto y honesto, para pintar la asignatura de un color
 *  sin que haya que interpretar tres números. */
export function subjectStatus(subject, grades) {
  const media = weightedAverage(grades);
  const restantes = absencesLeft(subject);

  if (restantes !== null && restantes < 0) {
    return { key: "absences", label: "Faltas pasadas", tone: "danger" };
  }
  if (media === null) return { key: "empty", label: "Sin notas", tone: "muted" };
  if (media < PASS_MARK) return { key: "failing", label: "Suspendiendo", tone: "danger" };
  if (media < 6) return { key: "tight", label: "Justo", tone: "warn" };
  if (media < 8) return { key: "ok", label: "Bien", tone: "ok" };
  return { key: "great", label: "Muy bien", tone: "great" };
}

// ── Eventos del curso ───────────────────────────────────────────────

export const EVENT_KINDS = {
  exam: { label: "Examen", icon: "📝", tone: "danger" },
  assignment: { label: "Entrega", icon: "📤", tone: "warn" },
  presentation: { label: "Presentación", icon: "🎤", tone: "info" },
  class: { label: "Clase", icon: "📚", tone: "muted" },
  tutoring: { label: "Tutoría", icon: "🧑‍🏫", tone: "info" },
  holiday: { label: "Fiesta", icon: "🎉", tone: "ok" },
};

export const eventKind = (k) => EVENT_KINDS[k] ?? EVENT_KINDS.exam;

/** Días naturales que faltan. Negativo = ya pasó.
 *  Se compara a comienzo de día: un examen a las 9:00 de mañana son
 *  "1 día", no "0 días" porque falten 16 horas. */
export function daysUntil(iso, hoy = new Date()) {
  const a = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const d = new Date(iso);
  const b = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return Math.round((b - a) / 86400000);
}

export function countdownLabel(iso, hoy = new Date()) {
  const dias = daysUntil(iso, hoy);
  if (dias < 0) return dias === -1 ? "ayer" : `hace ${Math.abs(dias)} días`;
  if (dias === 0) return "hoy";
  if (dias === 1) return "mañana";
  if (dias < 7) return `en ${dias} días`;
  if (dias < 14) return "en una semana";
  return `en ${Math.round(dias / 7)} semanas`;
}

/** Lo que viene, de lo más cercano a lo más lejano, sin lo que ya pasó. */
export function upcoming(events, hoy = new Date(), limite = 6) {
  return events
    .filter((e) => daysUntil(e.date, hoy) >= 0)
    .sort((a, b) => new Date(a.date) - new Date(b.date))
    .slice(0, limite);
}
