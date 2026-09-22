// Habitium — rutinas encadenadas.
//
// Todo el cálculo de horarios vive aquí, sin tocar el DOM ni la red, para
// poder probarlo de verdad (routines.test.mjs). La interfaz solo pinta lo
// que esto devuelve.
//
// ── El modelo, y por qué ────────────────────────────────────────────
//
// Una rutina tiene UNA hora de inicio (7:15) y cada paso tiene una
// DURACIÓN. No hay una hora guardada por paso, y es a propósito:
//
//   · Con una hora fija en cada paso, el día que te levantas diez minutos
//     tarde todos los avisos van desfasados y acabas silenciándolos. Y el
//     día que te duchas rápido, te quedas esperando.
//   · Con encadenado puro (cada paso arranca al marcar el anterior), el
//     PRIMER aviso no suena nunca: no hay nada que marcar antes de él.
//
// Con inicio + duraciones se pueden hacer las dos cosas a la vez: los
// avisos salen a la hora calculada, y en cuanto marcas un paso, los que
// quedan se recalculan DESDE ESE INSTANTE real. Si te duchas en cinco
// minutos, el aviso de los dientes se adelanta cinco minutos. Si te
// quedas dormido, todo se desplaza contigo en vez de gritarte.

/** Lunes = 1 … domingo = 7, como ISO. `Date.getDay()` devuelve domingo=0,
 *  que es la fuente de la mitad de los errores de calendario. */
export const diaISO = (fecha) => ((fecha.getDay() + 6) % 7) + 1;

export const NOMBRES_DIA = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"];

/** Cuánto cerca tiene que estar un paso para que valga decir "ahora".
 *  Un cuarto de hora a cada lado: lo justo para que sirva de aviso sin
 *  que la rutina de noche se pase el día diciendo que le toca. */
const VENTANA_AHORA_MIN = 15;

/** Pasado esto, un paso sin marcar ya no es "vas tarde", es "hoy no ha
 *  salido". Dos horas: el margen de alguien que se levanta tarde un
 *  sábado, no el de quien se saltó la rutina entera. */
const ABANDONADA_MIN = 120;

/** "7:15" a partir de 435. */
export function horaTexto(minutos) {
  const m = Math.max(0, Math.round(Number(minutos) || 0));
  const h = Math.floor(m / 60) % 24;
  return `${h}:${String(m % 60).padStart(2, "0")}`;
}

export function minutosDesdeTexto(texto) {
  const [h, m] = String(texto ?? "").split(":").map((x) => parseInt(x, 10));
  if (!Number.isFinite(h)) return null;
  return Math.min(1439, Math.max(0, h * 60 + (Number.isFinite(m) ? m : 0)));
}

/** ¿Toca hoy esta rutina? Una lista de días vacía significa "todos". */
export function tocaHoy(routine, fecha = new Date()) {
  const dias = routine?.days_of_week ?? [];
  if (!Array.isArray(dias) || dias.length === 0) return true;
  return dias.includes(diaISO(fecha));
}

/** El instante en que arranca la rutina en un día dado.
 *
 *  Se construye con `new Date(a, m, d, 0, 0)` y luego se suman minutos,
 *  en vez de pasar la hora al constructor. Suena a lo mismo y no lo es:
 *  el día que cambia la hora, las 2:30 pueden no existir (marzo) o existir
 *  dos veces (octubre), y el constructor tiene que inventarse una. Sumando
 *  minutos sobre medianoche, el reloj hace lo mismo que haría una persona
 *  mirándolo. */
export function inicioDelDia(routine, fecha = new Date()) {
  const base = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate(), 0, 0, 0, 0);
  return new Date(base.getTime() + (routine?.start_minutes ?? 0) * 60000);
}

/** Los pasos de una rutina, en orden y sin sorpresas. */
export function pasosDe(routine, steps) {
  return (steps ?? [])
    .filter((s) => s.routine_id === routine.id)
    .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0) || String(a.id).localeCompare(String(b.id)));
}

/** Los pasos marcados hoy, indexados por step_id → instante en que se
 *  marcó. Si un paso se marcó dos veces (dos dispositivos), vale el
 *  primero: es el que refleja cuándo se hizo de verdad. */
export function marcadosDelDia(routine, logs, fecha = new Date()) {
  const mapa = new Map();
  const y = fecha.getFullYear(), m = fecha.getMonth(), d = fecha.getDate();
  for (const log of logs ?? []) {
    if (log.routine_id !== routine.id) continue;
    const cuando = new Date(log.date);
    if (cuando.getFullYear() !== y || cuando.getMonth() !== m || cuando.getDate() !== d) continue;
    const previo = mapa.get(log.step_id);
    if (!previo || cuando < previo) mapa.set(log.step_id, cuando);
  }
  return mapa;
}

/**
 * EL CÁLCULO. Devuelve, para cada paso: a qué hora toca, si ya está
 * hecho, y si es el que está en marcha ahora mismo.
 *
 * La regla, en una frase: **el reloj lo pone el último paso marcado**.
 *
 *   · Los pasos ya marcados enseñan la hora REAL a la que se marcaron.
 *   · Los que quedan se encadenan a partir del último marcado —- no a
 *     partir de la hora teórica.
 *   · Si no hay ninguno marcado todavía, se encadenan desde la hora de
 *     inicio de la rutina, que es lo que hace que el primer aviso suene.
 *
 * Y un matiz que importa: si vas ADELANTADO (has marcado antes de la hora
 * teórica del siguiente paso), el siguiente NO se adelanta por debajo de
 * su hora teórica cuando la rutina depende del mundo exterior... salvo
 * que esa sea justamente la gracia. Aquí sí se adelanta: la rutina es
 * tuya y el encadenado es lo que pediste. Lo que no se hace nunca es
 * RETRASAR un paso por debajo de lo que ya ha pasado.
 */
export function horario(routine, steps, logs, ahora = new Date(), fecha = ahora) {
  const pasos = pasosDe(routine, steps);
  const marcados = marcadosDelDia(routine, logs, fecha);

  let reloj = inicioDelDia(routine, fecha);
  let ultimoMarcado = null;
  let yaHayPendiente = false;

  const filas = pasos.map((paso) => {
    const hecho = marcados.get(paso.id) ?? null;

    if (hecho) {
      // Un paso hecho manda sobre el reloj: lo que venga después se
      // cuenta desde que se marcó DE VERDAD, no desde lo previsto.
      ultimoMarcado = hecho;
      reloj = new Date(hecho.getTime() + (paso.duration_minutes ?? 0) * 60000);
      return { paso, hora: hecho, hecho: true, enMarcha: false, esAhora: false, previsto: false };
    }

    const hora = new Date(reloj.getTime());
    reloj = new Date(reloj.getTime() + (paso.duration_minutes ?? 0) * 60000);

    // "En marcha" es el primer paso sin marcar, y solo uno puede serlo.
    const enMarcha = !yaHayPendiente;
    yaHayPendiente = true;

    // Y "ahora" NO es lo mismo. El primer paso sin marcar de la rutina de
    // noche lo es también a las dos de la tarde, y ponerle la etiqueta
    // "ahora" a las 14:00 a algo que toca a las 22:30 es mentira.
    // "Ahora" es el paso en marcha cuyo momento está cerca de verdad.
    const esAhora = enMarcha && Math.abs(hora - ahora) <= VENTANA_AHORA_MIN * 60000;

    return {
      paso,
      hora,
      hecho: false,
      enMarcha,
      esAhora,
      // `previsto` distingue "esta hora sale de la plantilla" de "esta
      // hora sale de lo que ha pasado hoy". La interfaz lo usa para decir
      // "a las 7:25" frente a "a las 7:25 (recalculado)".
      previsto: ultimoMarcado === null,
    };
  });

  return filas;
}

/** ¿Está la rutina entera terminada hoy? Una rutina sin pasos NO cuenta
 *  como terminada: si no, aparecería premiada nada más crearla. */
export function completa(routine, steps, logs, fecha = new Date()) {
  const pasos = pasosDe(routine, steps);
  if (pasos.length === 0) return false;
  const marcados = marcadosDelDia(routine, logs, fecha);
  return pasos.every((p) => marcados.has(p.id));
}

/** Cuántos pasos llevas de cuántos. */
export function progreso(routine, steps, logs, fecha = new Date()) {
  const pasos = pasosDe(routine, steps);
  const marcados = marcadosDelDia(routine, logs, fecha);
  return { hechos: pasos.filter((p) => marcados.has(p.id)).length, total: pasos.length };
}

/** La racha: días seguidos terminando la rutina entera, contando hacia
 *  atrás desde hoy.
 *
 *  Los días que la rutina NO toca (fin de semana en una rutina de
 *  L-V) se SALTAN, no la rompen. Romperla el sábado por una rutina de
 *  días de colegio sería absurdo, y es el fallo que tienen la mitad de
 *  las apps de hábitos.
 *
 *  Y hoy no cuenta en contra: si aún no la has terminado pero el día no
 *  ha acabado, la racha es la de ayer. */
export function racha(routine, steps, logs, hoy = new Date(), maxDias = 400) {
  let dias = 0;
  let cursor = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());

  if (tocaHoy(routine, cursor) && !completa(routine, steps, logs, cursor)) {
    cursor.setDate(cursor.getDate() - 1);   // hoy todavía está a medias
  }

  for (let i = 0; i < maxDias; i++) {
    if (!tocaHoy(routine, cursor)) {
      cursor.setDate(cursor.getDate() - 1);
      continue;                              // día libre: ni suma ni rompe
    }
    if (!completa(routine, steps, logs, cursor)) break;
    dias++;
    cursor.setDate(cursor.getDate() - 1);
  }
  return dias;
}

// ═══ Avisos ═════════════════════════════════════════════════════════

/**
 * Los avisos que quedan por dar hoy, ya ordenados.
 *
 * Solo los que caen en el futuro: reprogramar uno que ya pasó haría que
 * sonaran todos de golpe al abrir la app por la tarde, que es de las
 * cosas que más rápido hacen que alguien quite los permisos.
 *
 * La excepción es `margenAtrasoMin`: un aviso que se pasó hace menos de
 * eso sí se da, porque el móvil pudo estar apagado justo en ese minuto y
 * enterarse dos minutos tarde sigue siendo útil.
 */
export function avisosPendientes(routine, steps, logs, ahora = new Date(), margenAtrasoMin = 0) {
  if (!routine?.is_active || !routine?.notifications_enabled) return [];
  if (!tocaHoy(routine, ahora)) return [];

  const limite = new Date(ahora.getTime() - margenAtrasoMin * 60000);

  return horario(routine, steps, logs, ahora)
    .filter((f) => !f.hecho && f.hora >= limite)
    .map((f, i, todos) => ({
      // El id es estable para el mismo paso y el mismo día: así se puede
      // reemplazar un aviso ya programado sin duplicarlo cuando el
      // horario se recalcula. La hora NO entra en el id justamente por
      // eso — si entrara, cada recálculo crearía un aviso nuevo.
      id: `rutina:${routine.id}:${f.paso.id}:${claveDia(ahora)}`,
      cuando: f.hora,
      titulo: `${f.paso.icon ?? "✅"} ${f.paso.title}`,
      cuerpo: textoDelAviso(routine, f, todos.length - i - 1),
      routineId: routine.id,
      stepId: f.paso.id,
    }));
}

/** Los avisos de todas las rutinas, juntos y en orden. */
export function todosLosAvisos(routines, steps, logs, ahora = new Date(), margenAtrasoMin = 0) {
  return (routines ?? [])
    .flatMap((r) => avisosPendientes(r, steps, logs, ahora, margenAtrasoMin))
    .sort((a, b) => a.cuando - b.cuando);
}

function textoDelAviso(routine, fila, quedanDespues) {
  if (quedanDespues === 0) return `Último paso de ${routine.name}. Ya está.`;
  const siguiente = quedanDespues === 1 ? "Queda uno más." : `Quedan ${quedanDespues} más.`;
  return `${routine.name} · ${siguiente}`;
}

export const claveDia = (fecha) =>
  `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, "0")}-${String(fecha.getDate()).padStart(2, "0")}`;

/** Texto corto para la tarjeta: "Empieza a las 7:15" / "Te toca ducharte"
 *  / "Hecha ✓". Es lo único que la mayoría de la gente va a leer. */
export function resumen(routine, steps, logs, ahora = new Date()) {
  if (!tocaHoy(routine, ahora)) return "Hoy no toca";

  const pasos = pasosDe(routine, steps);
  if (pasos.length === 0) return "Añade pasos para empezar";
  if (completa(routine, steps, logs, ahora)) return "Hecha ✓";

  const enMarcha = horario(routine, steps, logs, ahora).find((f) => f.enMarcha);
  if (!enMarcha) return "Hecha ✓";

  const minutos = Math.round((enMarcha.hora - ahora) / 60000);

  // Un atraso de horas no es un atraso, es que hoy no ha salido. Decir
  // "vas 392 minutos tarde" a las dos de la tarde no ayuda a nadie: solo
  // hace que la tarjeta parezca rota.
  if (minutos < -ABANDONADA_MIN) {
    const { hechos, total } = progreso(routine, steps, logs, ahora);
    return hechos === 0 ? "Hoy no ha salido" : `Se quedó en ${hechos} de ${total}`;
  }

  if (minutos > 60) return `Empieza a las ${horaTexto(routine.start_minutes)}`;
  if (minutos > 1) return `${enMarcha.paso.title}, en ${minutos} min`;
  if (minutos >= -1) return `Ahora: ${enMarcha.paso.title}`;
  return `${enMarcha.paso.title} — vas ${Math.abs(minutos)} min tarde`;
}

/** Duración total de la rutina, para enseñarla al configurarla. */
export function duracionTotal(routine, steps) {
  return pasosDe(routine, steps).reduce((s, p) => s + (p.duration_minutes ?? 0), 0);
}

/** Una rutina de ejemplo, que es la que pidió el caso original. Se ofrece
 *  al crear la primera: una rutina vacía no le dice nada a nadie. */
export const PLANTILLA_MANANA = {
  name: "Mañanas",
  icon: "☀️",
  start_minutes: 7 * 60 + 15,
  days_of_week: [1, 2, 3, 4, 5],
  pasos: [
    { title: "Levantarme", icon: "⏰", duration_minutes: 10 },
    { title: "Ducharme", icon: "🚿", duration_minutes: 15 },
    { title: "Lavarme los dientes", icon: "🪥", duration_minutes: 5 },
    { title: "Desayunar", icon: "🥣", duration_minutes: 20 },
  ],
};

export const PLANTILLA_NOCHE = {
  name: "Antes de dormir",
  icon: "🌙",
  start_minutes: 22 * 60 + 30,
  days_of_week: [1, 2, 3, 4, 5, 6, 7],
  pasos: [
    { title: "Dejar el móvil cargando lejos", icon: "📵", duration_minutes: 5 },
    { title: "Lavarme los dientes", icon: "🪥", duration_minutes: 5 },
    { title: "Preparar la mochila de mañana", icon: "🎒", duration_minutes: 10 },
    { title: "Leer un rato", icon: "📖", duration_minutes: 20 },
  ],
};
