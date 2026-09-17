// Pruebas del módulo de Estudios.
//
//   node --test web/study.test.mjs
//
// La media ponderada es la cuenta por la que la gente se monta una hoja
// de cálculo, y la que más se hace mal. Si esto se equivoca, alguien
// cree que aprueba cuando no, que es el peor fallo posible en esta app.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as s from "./study.js";

const nota = (score, weight, counts = true) => ({
  name: "x", score, weight, counts_for_average: counts,
});

test("la media se divide entre el peso evaluado, no entre 100", () => {
  // Medio curso hecho: 7 y 8 con 20 % cada uno.
  const notas = [nota(7, 20), nota(8, 20)];
  assert.equal(s.weightedAverage(notas), 7.5);
  // Dividir entre 100 daría 3, y diría "estás suspendiendo" a alguien
  // que va con un 7,5 de lo corregido. Es EL error de la hoja de cálculo.
  assert.notEqual(s.weightedAverage(notas), 3);
});

test("una nota que no cuenta se queda fuera de la media", () => {
  const notas = [nota(9, 50), nota(2, 50, false)];
  assert.equal(s.weightedAverage(notas), 9, "el 2 pendiente no debe hundir la media");
});

test("sin notas que cuenten, no hay media (y no es cero)", () => {
  assert.equal(s.weightedAverage([]), null);
  assert.equal(s.weightedAverage([nota(8, 30, false)]), null);
  assert.equal(s.weightedAverage([nota(8, 0)]), null, "peso 0 no aporta nada");
});

test("cuánto del curso llevas evaluado", () => {
  assert.equal(s.weightCovered([nota(7, 30), nota(8, 20)]), 0.5);
  assert.equal(s.weightCovered([]), 0);
  assert.equal(s.weightCovered([nota(7, 90), nota(8, 40)]), 1, "nunca pasa de 1");
});

test("los puntos acumulados son sobre la nota final", () => {
  // 7 que pesa 30 % = 2,1 puntos de los 10 finales.
  assert.equal(s.weightedPoints(nota(7, 30)), 2.1);
  assert.equal(s.weightedPoints(nota(7, 30, false)), 0);
  assert.ok(Math.abs(s.pointsSoFar([nota(7, 30), nota(6, 20)]) - 3.3) < 1e-9);
});

test("qué nota necesitas en lo que queda", () => {
  // Llevas 3,3 de 50 % hecho; para un 5 necesitas 3,4 en el 50 % que
  // queda, que es un 3,4 sobre 10.
  const notas = [nota(7, 30), nota(6, 20)];
  assert.ok(Math.abs(s.neededInRemaining(notas, 5) - 3.4) < 1e-9);
  // Con todo evaluado ya no queda nada que hacer.
  assert.equal(s.neededInRemaining([nota(4, 100)], 5), null);
});

test("si ya no llegas, lo dice en vez de disimular", () => {
  // Un 0 que pesa el 70 %: para un 5 harían falta más de 10 en el resto.
  const imposible = s.neededInRemaining([nota(0, 70)], 5);
  assert.ok(imposible > 10, `debería pasar de 10 y da ${imposible}`);
});

test("asistencia y faltas que te quedan", () => {
  assert.equal(s.attendance({ total_classes: 60, hours_missed: 6 }), 90);
  assert.equal(s.attendance({ total_classes: 0, hours_missed: 0 }), null);
  assert.equal(s.attendance({ total_classes: 10, hours_missed: 99 }), 0, "no baja de 0");
  assert.equal(s.absencesLeft({ max_absences: 12, hours_missed: 10 }), 2);
  assert.equal(s.absencesLeft({ max_absences: 12, hours_missed: 15 }), -3, "negativo = pasado");
  assert.equal(s.absencesLeft({ max_absences: 0 }), null);
});

test("el estado avisa de las faltas aunque la media sea buena", () => {
  const asignatura = { total_classes: 60, hours_missed: 14, max_absences: 12 };
  assert.equal(s.subjectStatus(asignatura, [nota(9, 50)]).key, "absences");
});

test("el estado sale de la media cuando las faltas van bien", () => {
  const ok = { total_classes: 60, hours_missed: 2, max_absences: 12 };
  assert.equal(s.subjectStatus(ok, []).key, "empty");
  assert.equal(s.subjectStatus(ok, [nota(4, 50)]).key, "failing");
  assert.equal(s.subjectStatus(ok, [nota(5.5, 50)]).key, "tight");
  assert.equal(s.subjectStatus(ok, [nota(7, 50)]).key, "ok");
  assert.equal(s.subjectStatus(ok, [nota(9, 50)]).key, "great");
});

test("la cuenta atrás va por días naturales, no por horas", () => {
  const hoy = new Date(2026, 8, 17, 23, 0);
  // Un examen a las 9:00 de mañana son 16 horas, pero es "mañana".
  assert.equal(s.countdownLabel(new Date(2026, 8, 18, 9, 0).toISOString(), hoy), "mañana");
  assert.equal(s.countdownLabel(new Date(2026, 8, 17, 8, 0).toISOString(), hoy), "hoy");
  assert.equal(s.countdownLabel(new Date(2026, 8, 20).toISOString(), hoy), "en 3 días");
  assert.equal(s.countdownLabel(new Date(2026, 8, 16).toISOString(), hoy), "ayer");
});

test("lo próximo se ordena y deja fuera lo que ya pasó", () => {
  const hoy = new Date(2026, 8, 17);
  const eventos = [
    { title: "lejano", date: new Date(2026, 9, 1).toISOString() },
    { title: "pasado", date: new Date(2026, 8, 1).toISOString() },
    { title: "cercano", date: new Date(2026, 8, 18).toISOString() },
  ];
  const lista = s.upcoming(eventos, hoy);
  assert.deepEqual(lista.map((e) => e.title), ["cercano", "lejano"]);
});

test("cada tipo de evento tiene etiqueta e icono", () => {
  for (const [key, k] of Object.entries(s.EVENT_KINDS)) {
    assert.ok(k.label && k.icon, key);
  }
  assert.equal(s.eventKind("inventado").label, "Examen", "tipo desconocido no rompe");
});
