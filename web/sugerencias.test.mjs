import { test } from "node:test";
import assert from "node:assert/strict";
import {
  validar, quedanHoy, ordenar, misVotos, haceCuanto, resumen, estadoDe, LIMITES,
} from "./sugerencias.js";

// ── Validar ─────────────────────────────────────────────────────────

test("una sugerencia normal pasa", () => {
  const r = validar({ title: "Modo oscuro automático", body: "A las 22:00.", author_name: "Álvaro" });
  assert.equal(r.ok, true);
  assert.deepEqual(r.errores, []);
  assert.equal(r.limpio.title, "Modo oscuro automático");
});

test("sin título no pasa", () => {
  const r = validar({ title: "" });
  assert.equal(r.ok, false);
  assert.match(r.errores[0], /título/i);
});

test("un título de solo espacios no cuela", () => {
  // Sin recortar antes de medir, veinte espacios pasarían el mínimo de 3.
  const r = validar({ title: "                    " });
  assert.equal(r.ok, false);
});

test("el título se recorta por los lados", () => {
  const r = validar({ title: "   Con espacios   " });
  assert.equal(r.limpio.title, "Con espacios");
});

test("un título de dos letras no llega al mínimo", () => {
  assert.equal(validar({ title: "ab" }).ok, false);
  assert.equal(validar({ title: "abc" }).ok, true);
});

test("el título largo dice por cuánto se pasa", () => {
  const r = validar({ title: "x".repeat(90) });
  assert.equal(r.ok, false);
  assert.match(r.errores[0], /10 caracteres/);
});

test("el texto largo también", () => {
  const r = validar({ title: "Vale", body: "y".repeat(520) });
  assert.equal(r.ok, false);
  assert.match(r.errores[0], /20 caracteres/);
});

test("sin nombre se firma Anónimo", () => {
  assert.equal(validar({ title: "Vale" }).limpio.author_name, "Anónimo");
  assert.equal(validar({ title: "Vale", author_name: "   " }).limpio.author_name, "Anónimo");
});

test("un tipo inventado no pasa", () => {
  const r = validar({ title: "Vale", kind: "urgentísimo" });
  assert.equal(r.ok, false);
});

test("se acumulan todos los problemas, no solo el primero", () => {
  const r = validar({ title: "", body: "y".repeat(600), author_name: "n".repeat(40) });
  assert.equal(r.errores.length, 3);
});

test("validar sin argumentos no revienta", () => {
  assert.equal(validar().ok, false);
});

// ── Cuántas quedan hoy ──────────────────────────────────────────────

const ahora = new Date("2026-09-23T18:00:00Z");
const haceHoras = (h) => new Date(ahora.getTime() - h * 3600_000).toISOString();

test("sin nada escrito quedan las cinco", () => {
  assert.equal(quedanHoy([], ahora), LIMITES.alDia);
  assert.equal(quedanHoy(null, ahora), 5);
});

test("tres escritas hoy dejan dos", () => {
  const mias = [1, 2, 3].map((h) => ({ created_at: haceHoras(h) }));
  assert.equal(quedanHoy(mias, ahora), 2);
});

test("las de hace más de un día no cuentan", () => {
  const mias = [25, 30, 48].map((h) => ({ created_at: haceHoras(h) }));
  assert.equal(quedanHoy(mias, ahora), 5);
});

test("la ventana son 24 h, no desde medianoche", () => {
  // Esta es la que importa: si contara "desde las 00:00", una escrita
  // ayer a las 23:00 no contaría y el servidor sí la contaría. La app
  // diría que te queda una y el servidor la rechazaría.
  const mias = [23.5, 23.9].map((h) => ({ created_at: haceHoras(h) }));
  assert.equal(quedanHoy(mias, ahora), 3);
});

test("nunca baja de cero", () => {
  const mias = Array.from({ length: 12 }, () => ({ created_at: haceHoras(1) }));
  assert.equal(quedanHoy(mias, ahora), 0);
});

// ── Ordenar ─────────────────────────────────────────────────────────

const YO = "yo-1111";
const OTRO = "otro-2222";

const buzon = [
  { id: "a", user_id: OTRO, title: "Tres votos, vieja", vote_count: 3, created_at: haceHoras(100) },
  { id: "b", user_id: YO, title: "Cero votos, nueva", vote_count: 0, created_at: haceHoras(1) },
  { id: "c", user_id: OTRO, title: "Tres votos, nueva", vote_count: 3, created_at: haceHoras(2) },
  { id: "d", user_id: YO, title: "Diez votos", vote_count: 10, created_at: haceHoras(50) },
];

test("por votos, y a igualdad de votos manda la más nueva", () => {
  const r = ordenar(buzon, "votadas").map((s) => s.id);
  assert.deepEqual(r, ["d", "c", "a", "b"]);
});

test("por nuevas, la más reciente primero", () => {
  const r = ordenar(buzon, "nuevas").map((s) => s.id);
  assert.deepEqual(r, ["b", "c", "d", "a"]);
});

test("las mías son solo las mías", () => {
  const r = ordenar(buzon, "mias", YO).map((s) => s.id);
  assert.deepEqual(r, ["b", "d"]);
});

test("las mías sin saber quién soy no devuelve nada de nadie", () => {
  assert.deepEqual(ordenar(buzon, "mias", null), []);
});

test("ordenar no toca la lista original", () => {
  const antes = buzon.map((s) => s.id);
  ordenar(buzon, "nuevas");
  assert.deepEqual(buzon.map((s) => s.id), antes);
});

test("una lista vacía o nula no revienta", () => {
  assert.deepEqual(ordenar([], "votadas"), []);
  assert.deepEqual(ordenar(null, "votadas"), []);
});

test("un modo desconocido cae en 'más votadas'", () => {
  assert.equal(ordenar(buzon, "loquesea")[0].id, "d");
});

// ── Mis votos ───────────────────────────────────────────────────────

test("mis votos salen en un conjunto", () => {
  const votos = [
    { suggestion_id: "a", user_id: YO },
    { suggestion_id: "c", user_id: OTRO },
    { suggestion_id: "d", user_id: YO },
  ];
  const mios = misVotos(votos, YO);
  assert.equal(mios.has("a"), true);
  assert.equal(mios.has("c"), false);
  assert.equal(mios.size, 2);
});

test("sin votos, conjunto vacío", () => {
  assert.equal(misVotos(null, YO).size, 0);
});

// ── Hace cuánto ─────────────────────────────────────────────────────

test("menos de un minuto es 'ahora mismo'", () => {
  assert.equal(haceCuanto(new Date(ahora.getTime() - 20_000), ahora), "ahora mismo");
});

test("un reloj adelantado no da 'hace -1 min'", () => {
  // Pasa de verdad: dos móviles nunca tienen la misma hora exacta.
  const futuro = new Date(ahora.getTime() + 30_000);
  assert.equal(haceCuanto(futuro, ahora), "ahora mismo");
});

test("minutos, horas, ayer, días y meses", () => {
  assert.equal(haceCuanto(haceHoras(0.5), ahora), "hace 30 min");
  assert.equal(haceCuanto(haceHoras(5), ahora), "hace 5 h");
  assert.equal(haceCuanto(haceHoras(30), ahora), "ayer");
  assert.equal(haceCuanto(haceHoras(24 * 5), ahora), "hace 5 días");
  assert.equal(haceCuanto(haceHoras(24 * 40), ahora), "hace un mes");
  assert.equal(haceCuanto(haceHoras(24 * 90), ahora), "hace 3 meses");
});

test("justo en la frontera de la hora", () => {
  assert.equal(haceCuanto(haceHoras(59 / 60), ahora), "hace 59 min");
  assert.equal(haceCuanto(haceHoras(1), ahora), "hace 1 h");
});

// ── Resumen y estados ───────────────────────────────────────────────

test("el resumen cuenta hechas y en camino", () => {
  const r = resumen([
    { status: "nueva" }, { status: "hecha" }, { status: "hecha" },
    { status: "en_camino" }, { status: "mirandolo" }, { status: "no" },
  ]);
  assert.deepEqual(r, { total: 6, hechas: 2, enCamino: 2 });
});

test("el resumen de un buzón vacío es todo ceros", () => {
  assert.deepEqual(resumen([]), { total: 0, hechas: 0, enCamino: 0 });
  assert.deepEqual(resumen(null), { total: 0, hechas: 0, enCamino: 0 });
});

test("un estado desconocido no deja la etiqueta en blanco", () => {
  // Si mañana añado un estado en la base y se me olvida aquí, que salga
  // "Nueva" y no un hueco vacío en la tarjeta.
  assert.equal(estadoDe("inventado").etiqueta, "Nueva");
  assert.equal(estadoDe(undefined).etiqueta, "Nueva");
  assert.equal(estadoDe("hecha").etiqueta, "Hecha");
});
