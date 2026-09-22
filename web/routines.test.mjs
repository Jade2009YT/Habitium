// Pruebas de routines.js.
//
//   node --test web/routines.test.mjs
//
// Lo que se prueba aquí es el cálculo del horario, que es donde una
// rutina encadenada se rompe en silencio: el día no cuadra, el aviso
// suena a destiempo, la racha se pierde el sábado. Nada de esto se ve
// leyendo el código, y con datos de mentira sí.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  diaISO, horaTexto, minutosDesdeTexto, tocaHoy, inicioDelDia,
  horario, completa, progreso, racha,
  avisosPendientes, todosLosAvisos, resumen, duracionTotal,
} from "./routines.js";

// ── Un caso de verdad: el que pidió el usuario ──────────────────────
// 7:15 me levanto → me ducho → me lavo los dientes → desayuno.
const RUTINA = {
  id: "r1",
  name: "Mañanas",
  icon: "☀️",
  start_minutes: 7 * 60 + 15,      // 435
  days_of_week: [1, 2, 3, 4, 5],   // de lunes a viernes
  is_active: true,
  notifications_enabled: true,
};

const PASOS = [
  { id: "s1", routine_id: "r1", title: "Levantarme", icon: "⏰", duration_minutes: 10, sort_order: 0 },
  { id: "s2", routine_id: "r1", title: "Ducharme", icon: "🚿", duration_minutes: 15, sort_order: 1 },
  { id: "s3", routine_id: "r1", title: "Dientes", icon: "🪥", duration_minutes: 5, sort_order: 2 },
  { id: "s4", routine_id: "r1", title: "Desayunar", icon: "🥣", duration_minutes: 20, sort_order: 3 },
];

// Un miércoles cualquiera, para que la rutina de L-V toque.
const MIERCOLES = (h = 7, m = 0) => new Date(2026, 8, 23, h, m, 0, 0);
const log = (stepId, h, m, dia = MIERCOLES()) => ({
  id: `l-${stepId}-${h}${m}`,
  routine_id: "r1",
  step_id: stepId,
  date: new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), h, m).toISOString(),
});

const horas = (filas) => filas.map((f) => horaTexto(f.hora.getHours() * 60 + f.hora.getMinutes()));

// ═══ Lo básico ══════════════════════════════════════════════════════

test("el lunes es 1 y el domingo es 7, no al revés", () => {
  assert.equal(diaISO(new Date(2026, 8, 21)), 1);   // lunes
  assert.equal(diaISO(new Date(2026, 8, 27)), 7);   // domingo
});

test("435 minutos son las 7:15", () => {
  assert.equal(horaTexto(435), "7:15");
  assert.equal(minutosDesdeTexto("7:15"), 435);
  assert.equal(minutosDesdeTexto("07:05"), 425);
});

test("una hora imposible se recorta en vez de dar la vuelta", () => {
  assert.equal(minutosDesdeTexto("99:99"), 1439);
  assert.equal(minutosDesdeTexto("no es una hora"), null);
});

test("una rutina de L-V no toca el sábado", () => {
  assert.equal(tocaHoy(RUTINA, new Date(2026, 8, 23)), true);   // miércoles
  assert.equal(tocaHoy(RUTINA, new Date(2026, 8, 26)), false);  // sábado
});

test("sin días marcados, toca todos", () => {
  assert.equal(tocaHoy({ days_of_week: [] }, new Date(2026, 8, 26)), true);
  assert.equal(tocaHoy({}, new Date(2026, 8, 26)), true);
});

test("la rutina empieza a su hora, no a la del servidor", () => {
  const inicio = inicioDelDia(RUTINA, MIERCOLES());
  assert.equal(inicio.getHours(), 7);
  assert.equal(inicio.getMinutes(), 15);
});

// ═══ El horario, que es lo importante ═══════════════════════════════

test("sin nada marcado, los pasos se encadenan desde la hora de inicio", () => {
  const filas = horario(RUTINA, PASOS, [], MIERCOLES(6, 0));
  assert.deepEqual(horas(filas), ["7:15", "7:25", "7:40", "7:45"]);
});

test("solo un paso está 'en marcha', y es el primero sin marcar", () => {
  const filas = horario(RUTINA, PASOS, [], MIERCOLES(6, 0));
  assert.deepEqual(filas.map((f) => f.enMarcha), [true, false, false, false]);
});

test("marcar un paso ANTES de tiempo adelanta todos los siguientes", () => {
  // Se levanta a las 7:15 y se ducha a las 7:20 (cinco minutos antes de
  // lo previsto). Los dientes deberían adelantarse también.
  const logs = [log("s1", 7, 15), log("s2", 7, 20)];
  const filas = horario(RUTINA, PASOS, logs, MIERCOLES(7, 30));

  assert.deepEqual(horas(filas), ["7:15", "7:20", "7:35", "7:40"]);
  assert.equal(filas[2].enMarcha, true, "los dientes son el paso en marcha");
});

test("marcar un paso TARDE desplaza los siguientes, no los deja atrás", () => {
  // Se queda dormido: marca "levantarme" a las 7:40, 25 minutos tarde.
  const logs = [log("s1", 7, 40)];
  const filas = horario(RUTINA, PASOS, logs, MIERCOLES(7, 45));

  assert.deepEqual(horas(filas), ["7:40", "7:50", "8:05", "8:10"]);
});

test("un paso hecho enseña la hora REAL, no la teórica", () => {
  const filas = horario(RUTINA, PASOS, [log("s1", 7, 40)], MIERCOLES(7, 45));
  assert.equal(filas[0].hecho, true);
  assert.equal(filas[0].hora.getHours(), 7);
  assert.equal(filas[0].hora.getMinutes(), 40);
});

test("antes de marcar nada, las horas están marcadas como 'previstas'", () => {
  const sinNada = horario(RUTINA, PASOS, [], MIERCOLES(6, 0));
  assert.deepEqual(sinNada.map((f) => f.previsto), [true, true, true, true]);

  // En cuanto hay un paso marcado, los siguientes ya no son plantilla:
  // salen de lo que ha pasado hoy de verdad.
  const conUno = horario(RUTINA, PASOS, [log("s1", 7, 40)], MIERCOLES(7, 45));
  assert.deepEqual(conUno.map((f) => f.previsto), [false, false, false, false]);
});

test("marcar un paso del medio saltándose el anterior no rompe el orden", () => {
  // Se ducha sin marcar que se ha levantado. El primer paso sigue
  // pendiente y el reloj lo pone la ducha.
  const filas = horario(RUTINA, PASOS, [log("s2", 7, 30)], MIERCOLES(7, 35));
  assert.equal(filas[0].hecho, false);
  assert.equal(filas[1].hecho, true);
  assert.deepEqual(horas(filas).slice(2), ["7:45", "7:50"]);
});

test("los pasos se ordenan por sort_order aunque lleguen desordenados", () => {
  const revueltos = [PASOS[3], PASOS[0], PASOS[2], PASOS[1]];
  const filas = horario(RUTINA, revueltos, [], MIERCOLES(6, 0));
  assert.deepEqual(filas.map((f) => f.paso.title),
    ["Levantarme", "Ducharme", "Dientes", "Desayunar"]);
});

test("los pasos de OTRA rutina no se cuelan", () => {
  const ajeno = { id: "x", routine_id: "r2", title: "De otra", duration_minutes: 5, sort_order: 0 };
  const filas = horario(RUTINA, [...PASOS, ajeno], [], MIERCOLES(6, 0));
  assert.equal(filas.length, 4);
});

test("un log de AYER no cuenta como hecho hoy", () => {
  const ayer = new Date(2026, 8, 22, 7, 15);
  const filas = horario(RUTINA, PASOS, [log("s1", 7, 15, ayer)], MIERCOLES(7, 0));
  assert.equal(filas[0].hecho, false, "lo de ayer no se arrastra a hoy");
});

test("marcar dos veces el mismo paso vale la primera vez", () => {
  // Dos dispositivos sincronizando pueden dejar dos filas. La buena es la
  // de antes: es cuando se hizo de verdad.
  const logs = [log("s1", 7, 40), log("s1", 7, 15)];
  const filas = horario(RUTINA, PASOS, logs, MIERCOLES(8, 0));
  assert.equal(filas[0].hora.getMinutes(), 15);
});

test("una rutina sin pasos no revienta", () => {
  assert.deepEqual(horario(RUTINA, [], [], MIERCOLES()), []);
});

// ═══ Progreso, completa y racha ═════════════════════════════════════

test("completa solo cuando están TODOS los pasos", () => {
  const casi = [log("s1", 7, 15), log("s2", 7, 25), log("s3", 7, 40)];
  assert.equal(completa(RUTINA, PASOS, casi, MIERCOLES()), false);
  assert.equal(completa(RUTINA, PASOS, [...casi, log("s4", 7, 45)], MIERCOLES()), true);
});

test("una rutina SIN pasos no cuenta como completa", () => {
  // Si contara, aparecería premiada nada más crearla.
  assert.equal(completa(RUTINA, [], [], MIERCOLES()), false);
});

test("el progreso dice cuántos de cuántos", () => {
  assert.deepEqual(progreso(RUTINA, PASOS, [log("s1", 7, 15)], MIERCOLES()), { hechos: 1, total: 4 });
});

test("la racha cuenta días seguidos terminados", () => {
  const todos = (dia) => PASOS.map((p, i) => log(p.id, 7, 15 + i * 10, dia));
  const logs = [
    ...todos(new Date(2026, 8, 21)),   // lunes
    ...todos(new Date(2026, 8, 22)),   // martes
    ...todos(new Date(2026, 8, 23)),   // miércoles (hoy)
  ];
  assert.equal(racha(RUTINA, PASOS, logs, MIERCOLES(9, 0)), 3);
});

test("el fin de semana NO rompe la racha de una rutina de L-V", () => {
  // Este es el fallo que tienen la mitad de las apps de hábitos: te
  // castigan el sábado por una rutina que solo es de días de colegio.
  const todos = (dia) => PASOS.map((p, i) => log(p.id, 7, 15 + i * 10, dia));
  const logs = [
    ...todos(new Date(2026, 8, 17)),   // jueves
    ...todos(new Date(2026, 8, 18)),   // viernes
    // sábado y domingo sin nada: la rutina no toca
    ...todos(new Date(2026, 8, 21)),   // lunes
  ];
  assert.equal(racha(RUTINA, PASOS, logs, new Date(2026, 8, 21, 9, 0)), 3);
});

test("hoy a medias no rompe la racha: todavía queda día", () => {
  const todos = (dia) => PASOS.map((p, i) => log(p.id, 7, 15 + i * 10, dia));
  const logs = [
    ...todos(new Date(2026, 8, 21)),
    ...todos(new Date(2026, 8, 22)),
    log("s1", 7, 15),                  // hoy solo el primero
  ];
  assert.equal(racha(RUTINA, PASOS, logs, MIERCOLES(7, 30)), 2);
});

test("un día saltado sí rompe la racha", () => {
  const todos = (dia) => PASOS.map((p, i) => log(p.id, 7, 15 + i * 10, dia));
  const logs = [
    ...todos(new Date(2026, 8, 21)),   // lunes
    // martes: nada
    ...todos(new Date(2026, 8, 23)),   // miércoles
  ];
  assert.equal(racha(RUTINA, PASOS, logs, MIERCOLES(9, 0)), 1);
});

test("sin nada hecho nunca, la racha es cero (y no da vueltas eternas)", () => {
  assert.equal(racha(RUTINA, PASOS, [], MIERCOLES(9, 0)), 0);
});

// ═══ Avisos ═════════════════════════════════════════════════════════

test("a primera hora quedan los cuatro avisos", () => {
  const avisos = avisosPendientes(RUTINA, PASOS, [], MIERCOLES(6, 0));
  assert.equal(avisos.length, 4);
  assert.equal(avisos[0].titulo, "⏰ Levantarme");
});

test("los avisos que ya pasaron NO se reprograman", () => {
  // Si se reprogramaran, abrir la app por la tarde dispararía los cuatro
  // de golpe — y ahí es cuando la gente quita los permisos.
  const avisos = avisosPendientes(RUTINA, PASOS, [], MIERCOLES(12, 0));
  assert.equal(avisos.length, 0);
});

test("pero uno que se pasó hace un minuto sí se da, con margen", () => {
  // El móvil pudo estar apagado justo en ese minuto.
  const avisos = avisosPendientes(RUTINA, PASOS, [], MIERCOLES(7, 16), 5);
  assert.equal(avisos[0].titulo, "⏰ Levantarme");
});

test("un paso ya hecho no genera aviso", () => {
  const avisos = avisosPendientes(RUTINA, PASOS, [log("s1", 7, 15)], MIERCOLES(7, 16));
  assert.deepEqual(avisos.map((a) => a.stepId), ["s2", "s3", "s4"]);
});

test("el id del aviso NO cambia al recalcular el horario", () => {
  // Es lo que permite reemplazar un aviso ya programado en vez de
  // duplicarlo. Si la hora entrara en el id, cada recálculo crearía uno
  // nuevo y acabarías con cinco avisos del mismo paso.
  const antes = avisosPendientes(RUTINA, PASOS, [], MIERCOLES(6, 0));
  const despues = avisosPendientes(RUTINA, PASOS, [log("s1", 7, 40)], MIERCOLES(7, 41));
  const idDucha = (l) => l.find((a) => a.stepId === "s2").id;
  assert.equal(idDucha(antes), idDucha(despues));
});

test("una rutina apagada no avisa", () => {
  assert.deepEqual(avisosPendientes({ ...RUTINA, is_active: false }, PASOS, [], MIERCOLES(6, 0)), []);
  assert.deepEqual(avisosPendientes({ ...RUTINA, notifications_enabled: false }, PASOS, [], MIERCOLES(6, 0)), []);
});

test("el sábado no avisa una rutina de L-V", () => {
  assert.deepEqual(avisosPendientes(RUTINA, PASOS, [], new Date(2026, 8, 26, 6, 0)), []);
});

test("el último paso lo dice, para que se sepa que ya está", () => {
  const avisos = avisosPendientes(RUTINA, PASOS, [], MIERCOLES(6, 0));
  assert.match(avisos[3].cuerpo, /Último paso/);
  assert.match(avisos[0].cuerpo, /Quedan 3 más/);
});

test("los avisos de varias rutinas salen mezclados y en orden", () => {
  const noche = { ...RUTINA, id: "r2", name: "Noche", start_minutes: 22 * 60, days_of_week: [] };
  const pasosNoche = [{ id: "n1", routine_id: "r2", title: "Dientes", duration_minutes: 5, sort_order: 0 }];
  const avisos = todosLosAvisos([RUTINA, noche], [...PASOS, ...pasosNoche], [], MIERCOLES(6, 0));

  assert.equal(avisos.length, 5);
  for (let i = 1; i < avisos.length; i++) {
    assert.ok(avisos[i].cuando >= avisos[i - 1].cuando, "deberían venir ordenados por hora");
  }
  assert.equal(avisos.at(-1).routineId, "r2");
});

// ═══ El texto que lee la gente ══════════════════════════════════════

test("el resumen cambia según el momento", () => {
  assert.equal(resumen(RUTINA, PASOS, [], MIERCOLES(5, 0)), "Empieza a las 7:15");
  assert.equal(resumen(RUTINA, PASOS, [], MIERCOLES(7, 5)), "Levantarme, en 10 min");
  assert.equal(resumen(RUTINA, PASOS, [], MIERCOLES(7, 15)), "Ahora: Levantarme");
  assert.match(resumen(RUTINA, PASOS, [], MIERCOLES(7, 45)), /vas 30 min tarde/);
});

test("el resumen dice cuándo está hecha y cuándo no toca", () => {
  const todos = PASOS.map((p, i) => log(p.id, 7, 15 + i * 10));
  assert.equal(resumen(RUTINA, PASOS, todos, MIERCOLES(9, 0)), "Hecha ✓");
  assert.equal(resumen(RUTINA, PASOS, [], new Date(2026, 8, 26, 9, 0)), "Hoy no toca");
  assert.equal(resumen(RUTINA, [], [], MIERCOLES(9, 0)), "Añade pasos para empezar");
});

test("la duración total suma los pasos", () => {
  assert.equal(duracionTotal(RUTINA, PASOS), 50);
});

// ═══ "Ahora" no es "el siguiente" ═══════════════════════════════════

test("la etiqueta 'ahora' solo sale si el paso toca de verdad ahora", () => {
  // A las 7:15 el primer paso es el de ahora.
  const aLaHora = horario(RUTINA, PASOS, [], MIERCOLES(7, 15));
  assert.equal(aLaHora[0].esAhora, true);

  // A las 14:00 el primer paso sigue siendo "el siguiente sin marcar",
  // pero decir "ahora" a las dos de la tarde sería mentira.
  const porLaTarde = horario(RUTINA, PASOS, [], MIERCOLES(14, 0));
  assert.equal(porLaTarde[0].enMarcha, true, "sigue siendo el siguiente");
  assert.equal(porLaTarde[0].esAhora, false, "pero no es 'ahora'");
});

test("una rutina de noche no dice 'ahora' por la mañana", () => {
  // Este era el fallo que se veía en pantalla: la rutina de las 22:30
  // marcaba su primer paso como "ahora" a las dos de la tarde.
  const noche = { ...RUTINA, id: "r2", start_minutes: 22 * 60 + 30, days_of_week: [] };
  const pasosNoche = [{ id: "n1", routine_id: "r2", title: "Dientes", duration_minutes: 5, sort_order: 0 }];
  assert.equal(horario(noche, pasosNoche, [], MIERCOLES(14, 0))[0].esAhora, false);
  assert.equal(horario(noche, pasosNoche, [], MIERCOLES(22, 30))[0].esAhora, true);
});

test("un paso ya hecho nunca es 'ahora'", () => {
  const filas = horario(RUTINA, PASOS, [log("s1", 7, 15)], MIERCOLES(7, 16));
  assert.equal(filas[0].esAhora, false);
});

// ═══ Un atraso de horas no es un atraso ═════════════════════════════

test("por la tarde no dice 'vas 392 minutos tarde'", () => {
  // Lo que salía antes en pantalla, y hacía que la tarjeta pareciera rota.
  const texto = resumen(RUTINA, PASOS, [], MIERCOLES(14, 0));
  assert.doesNotMatch(texto, /min tarde/);
  assert.equal(texto, "Hoy no ha salido");
});

test("si quedó a medias, lo dice con números", () => {
  const logs = [log("s1", 7, 15), log("s2", 7, 25)];
  assert.equal(resumen(RUTINA, PASOS, logs, MIERCOLES(14, 0)), "Se quedó en 2 de 4");
});

test("pero un atraso de verdad sí se dice en minutos", () => {
  // Media hora tarde sigue siendo recuperable: eso hay que decirlo.
  assert.match(resumen(RUTINA, PASOS, [], MIERCOLES(7, 45)), /vas 30 min tarde/);
});
