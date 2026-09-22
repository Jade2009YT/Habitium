// Pruebas de nutricion-ia.js.
//
//   node --test web/nutricion-ia.test.mjs
//
// Lo importante de este archivo no es la fórmula: es EL CERROJO. Lo que
// se prueba es qué pasa cuando la IA devuelve un disparate, porque eso
// va a pasar antes o después, y el disparate se lo come un chaval de 16
// años en forma de objetivo diario.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PREGUNTAS, metabolismoBasal, gastoDiario, objetivoDeReferencia,
  acotarObjetivo, validarRespuestas, momentoDelDia, normalizarComida,
  promptObjetivo, promptRecomendacion,
} from "./nutricion-ia.js";

// Un caso realista: chaval de 16 años, entrena tres días, quiere ganar.
const ALVARO = { objetivo: "ganar", sexo: "hombre", edad: 16, altura: 178, peso: 68, actividad: "moderado", notas: "" };
const MUJER = { objetivo: "perder", sexo: "mujer", edad: 17, altura: 165, peso: 62, actividad: "ligero", notas: "" };

// ═══ La fórmula ═════════════════════════════════════════════════════

test("Mifflin-St Jeor da el número conocido", () => {
  // 10·68 + 6.25·178 − 5·16 + 5 = 680 + 1112.5 − 80 + 5 = 1717.5 → 1718
  assert.equal(metabolismoBasal(ALVARO), 1718);
});

test("la fórmula distingue hombre de mujer", () => {
  const h = metabolismoBasal({ ...MUJER, sexo: "hombre" });
  const m = metabolismoBasal(MUJER);
  assert.equal(h - m, 166, "la diferencia de la fórmula son 166 kcal");
});

test("moverse más sube el gasto", () => {
  const quieto = gastoDiario({ ...ALVARO, actividad: "sedentario" });
  const atleta = gastoDiario({ ...ALVARO, actividad: "atleta" });
  assert.ok(atleta > quieto * 1.5, `${atleta} debería superar bastante a ${quieto}`);
});

test("querer perder da menos calorías que mantener, y ganar más", () => {
  const perder = objetivoDeReferencia({ ...ALVARO, objetivo: "perder" }).calorias;
  const mantener = objetivoDeReferencia({ ...ALVARO, objetivo: "mantener" }).calorias;
  const ganar = objetivoDeReferencia({ ...ALVARO, objetivo: "ganar" }).calorias;
  assert.ok(perder < mantener && mantener < ganar, `${perder} < ${mantener} < ${ganar}`);
});

test("ni queriendo perder se baja del metabolismo basal", () => {
  // Alguien pequeño y sedentario: es donde el déficit del 15% podría
  // colarse por debajo del basal.
  const pequeña = { objetivo: "perder", sexo: "mujer", edad: 45, altura: 150, peso: 48, actividad: "sedentario" };
  const objetivo = objetivoDeReferencia(pequeña);
  assert.ok(objetivo.calorias >= metabolismoBasal(pequeña),
    `${objetivo.calorias} no debería bajar de ${metabolismoBasal(pequeña)}`);
});

test("los macros de referencia suman las calorías", () => {
  const o = objetivoDeReferencia(ALVARO);
  const suma = o.proteina * 4 + o.carbos * 4 + o.grasa * 9;
  assert.ok(Math.abs(suma - o.calorias) <= o.calorias * 0.05,
    `los macros suman ${suma} y el objetivo es ${o.calorias}`);
});

// ═══ EL CERROJO: qué pasa cuando la IA dice un disparate ════════════

test("una IA que propone 900 kcal no se sale con la suya", () => {
  // El caso peligroso de verdad: el modelo se cree que "adelgazar
  // rápido" es un objetivo legítimo.
  const { objetivo, avisos } = acotarObjetivo(
    { calorias: 900, proteina: 60, carbos: 80, grasa: 20 }, ALVARO
  );
  assert.ok(objetivo.calorias >= metabolismoBasal(ALVARO),
    `${objetivo.calorias} sigue por debajo del basal`);
  assert.ok(avisos.some((a) => /por debajo de lo que tu cuerpo gasta/.test(a)),
    "y la app tiene que decirlo, no corregirlo a escondidas");
});

test("una IA que propone 9000 kcal tampoco", () => {
  const { objetivo, avisos } = acotarObjetivo(
    { calorias: 9000, proteina: 300, carbos: 900, grasa: 300 }, ALVARO
  );
  assert.ok(objetivo.calorias <= gastoDiario(ALVARO) * 2);
  assert.ok(avisos.some((a) => /más del doble/.test(a)));
});

test("la proteína se acota por kilo de peso, no por porcentaje", () => {
  const bajo = acotarObjetivo({ calorias: 2500, proteina: 10, carbos: 300, grasa: 80 }, ALVARO);
  assert.ok(bajo.objetivo.proteina >= Math.round(68 * 0.8));

  const alto = acotarObjetivo({ calorias: 2500, proteina: 500, carbos: 100, grasa: 80 }, ALVARO);
  assert.ok(alto.objetivo.proteina <= Math.round(68 * 3));
});

test("la grasa nunca baja del 15% de las calorías", () => {
  // La grasa es la primera que recorta todo el mundo y la que hace que
  // funcionen las hormonas.
  const { objetivo, avisos } = acotarObjetivo(
    { calorias: 2400, proteina: 140, carbos: 400, grasa: 5 }, ALVARO
  );
  assert.ok(objetivo.grasa * 9 >= objetivo.calorias * 0.14);
  assert.ok(avisos.some((a) => /hormonas/.test(a)));
});

test("si los macros no cuadran con las calorías, se recalculan", () => {
  // 100·4 + 100·4 + 10·9 = 890, muy lejos de 2500.
  const { objetivo, avisos } = acotarObjetivo(
    { calorias: 2500, proteina: 100, carbos: 100, grasa: 10 }, ALVARO
  );
  const suma = objetivo.proteina * 4 + objetivo.carbos * 4 + objetivo.grasa * 9;
  assert.ok(Math.abs(suma - objetivo.calorias) <= objetivo.calorias * 0.12,
    `${suma} frente a ${objetivo.calorias}`);
  assert.ok(avisos.length > 0);
});

test("una respuesta razonable pasa sin tocarla ni avisar", () => {
  // El cerrojo no puede ser tan estrecho que corrija siempre: si avisara
  // de todo, nadie leería los avisos.
  const buena = objetivoDeReferencia(ALVARO);
  const { objetivo, avisos } = acotarObjetivo(buena, ALVARO);
  assert.deepEqual(objetivo, buena);
  assert.equal(avisos.length, 0);
});

test("basura, null y texto no rompen nada: se cae al valor de referencia", () => {
  const referencia = objetivoDeReferencia(ALVARO);
  for (const basura of [null, undefined, {}, { calorias: "muchas" }, { calorias: -50 }, { calorias: NaN }]) {
    const { objetivo } = acotarObjetivo(basura, ALVARO);
    assert.equal(objetivo.calorias, referencia.calorias, `falló con ${JSON.stringify(basura)}`);
  }
});

// ═══ El cuestionario ════════════════════════════════════════════════

test("no se gasta una llamada a la IA con el cuestionario a medias", () => {
  assert.equal(validarRespuestas({ objetivo: "ganar" }).valido, false);
  assert.equal(validarRespuestas(ALVARO).valido, true);
});

test("un peso imposible se rechaza antes de llegar a la IA", () => {
  assert.equal(validarRespuestas({ ...ALVARO, peso: 500 }).valido, false);
  assert.equal(validarRespuestas({ ...ALVARO, edad: 3 }).valido, false);
  assert.deepEqual(validarRespuestas({ ...ALVARO, altura: 10 }).faltan, ["altura"]);
});

test("una opción inventada no cuela", () => {
  assert.equal(validarRespuestas({ ...ALVARO, actividad: "superman" }).valido, false);
});

test("las notas son opcionales de verdad", () => {
  const sinNotas = { ...ALVARO };
  delete sinNotas.notas;
  assert.equal(validarRespuestas(sinNotas).valido, true);
});

test("todas las preguntas tienen lo que la interfaz necesita para pintarlas", () => {
  for (const p of PREGUNTAS) {
    assert.ok(p.id && p.texto && p.tipo, `la pregunta ${p.id} está incompleta`);
    if (p.tipo === "opciones") assert.ok(p.opciones?.length >= 2, `${p.id} necesita opciones`);
    if (p.tipo === "numero") assert.ok(p.min < p.max, `${p.id} tiene un rango imposible`);
  }
});

// ═══ Lo que se le manda a la IA ═════════════════════════════════════

test("el prompt del objetivo lleva la referencia calculada", () => {
  // Es lo que evita que el modelo se invente el número desde cero: se le
  // da el resultado de la fórmula como punto de partida.
  const texto = promptObjetivo(ALVARO).map((m) => m.content).join("\n");
  assert.match(texto, /Mifflin-St Jeor/);
  assert.match(texto, new RegExp(String(metabolismoBasal(ALVARO))));
});

test("el prompt de recomendación lleva lo que QUEDA, no solo lo comido", () => {
  const texto = promptRecomendacion({
    objetivo: { calorias: 2600, proteina: 130, carbos: 300, grasa: 80 },
    consumido: { calorias: 1800, proteina: 90, carbos: 200, grasa: 60 },
    momento: "cena",
    respuestas: ALVARO,
    comidasDeHoy: ["Tostadas", "Pasta con pollo"],
  }).map((m) => m.content).join("\n");

  assert.match(texto, /800 kcal/, "lo que queda de calorías");
  assert.match(texto, /Pasta con pollo/, "y lo que ya ha comido");
});

test("si ya te has pasado del objetivo, no salen números negativos", () => {
  const texto = promptRecomendacion({
    objetivo: { calorias: 2000, proteina: 100, carbos: 200, grasa: 60 },
    consumido: { calorias: 2500, proteina: 150, carbos: 300, grasa: 90 },
    momento: "cena",
    respuestas: ALVARO,
  }).map((m) => m.content).join("\n");
  assert.doesNotMatch(texto, /-\d+ kcal/);
});

// ═══ Fotos y horarios ═══════════════════════════════════════════════

test("un plato de 40.000 calorías se recorta", () => {
  const c = normalizarComida({ nombre: "Paella", calorias: 40000, proteina: -5, carbos: "muchos", grasa: 20 });
  assert.ok(c.calorias <= 5000);
  assert.equal(c.proteina, 0, "un negativo se queda en cero");
  assert.equal(c.carbos, 0, "y un texto también");
  assert.equal(c.grasa, 20);
});

test("una respuesta vacía de la IA no deja la comida sin nombre", () => {
  assert.equal(normalizarComida(null).nombre, "Comida");
  assert.equal(normalizarComida({}).confianza, "media");
});

test("un nombre kilométrico se corta antes de llegar a la base", () => {
  // El servidor tiene un CHECK de 120 caracteres en food_entries.name:
  // sin esto, la fila se rechazaría y la comida se perdería.
  assert.ok(normalizarComida({ nombre: "a".repeat(500) }).nombre.length <= 120);
});

test("el momento del día usa horarios españoles", () => {
  assert.equal(momentoDelDia(new Date(2026, 0, 1, 9)), "desayuno");
  assert.equal(momentoDelDia(new Date(2026, 0, 1, 14, 30)), "comida");
  assert.equal(momentoDelDia(new Date(2026, 0, 1, 18)), "merienda");
  assert.equal(momentoDelDia(new Date(2026, 0, 1, 21, 30)), "cena");
});
