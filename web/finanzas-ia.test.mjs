// Pruebas de finanzas-ia.js.
//
//   node --test web/finanzas-ia.test.mjs
//
// Lo que importa aquí no es que las divisiones estén bien: es qué pasa
// cuando el objetivo NO cabe. Una app que te dice "sí, puedes ahorrar
// 300 € al mes" cuando te entran 200 no te está ayudando — te está
// preparando para fallar en enero y dejarlo.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PREGUNTAS, CATEGORIAS, validarRespuestas, calcularPlan, avisosDelPlan,
  estadoDelMes, porCategoria, recortables, interpretarGasto, normalizarGasto,
  promptPlan,
} from "./finanzas-ia.js";

// Un caso realista: 250 € de paga, gasta 180, quiere 600 € en 6 meses.
const HOLGADO = { ahorroActual: 100, ingresoMensual: 250, gastoMensual: 180, objetivo: 600, meses: 12, meta: "viaje", notas: "" };
const IMPOSIBLE = { ahorroActual: 0, ingresoMensual: 200, gastoMensual: 180, objetivo: 3000, meses: 6, meta: "compra", notas: "" };
const ENROJO = { ahorroActual: 50, ingresoMensual: 200, gastoMensual: 260, objetivo: 1000, meses: 12, meta: "colchon", notas: "" };

// ═══ Las cuentas ════════════════════════════════════════════════════

test("un plan que cabe sale viable y con su cuota", () => {
  const plan = calcularPlan(HOLGADO);
  assert.equal(plan.margen, 70, "le sobran 70 € al mes");
  assert.equal(plan.falta, 500, "le faltan 500 € para los 600");
  assert.ok(Math.abs(plan.porMes - 41.67) < 0.02, `${plan.porMes} ≈ 41,67 al mes`);
  assert.equal(plan.viable, true);
});

test("un plan que no cabe se marca como NO viable", () => {
  const plan = calcularPlan(IMPOSIBLE);
  assert.equal(plan.margen, 20);
  assert.equal(plan.necesarioPorMes, 500, "harían falta 500 al mes");
  assert.equal(plan.viable, false);
});

test("y dice en cuántos meses llegaría de verdad", () => {
  // 3000 € a 20 € al mes son 150 meses. Decirlo es más útil que un "no".
  assert.equal(calcularPlan(IMPOSIBLE).mesesReales, 150);
});

test("gastando más de lo que entra, NO se inventa un plazo negativo", () => {
  // Dividir entre un margen negativo daría "llegas en -12 meses", que es
  // la clase de mentira matemática que hace que una app parezca rota.
  const plan = calcularPlan(ENROJO);
  assert.equal(plan.margen, -60);
  assert.equal(plan.mesesReales, null);
  assert.equal(plan.viable, false);
});

test("el presupuesto nunca sale negativo", () => {
  for (const r of [HOLGADO, IMPOSIBLE, ENROJO]) {
    assert.ok(calcularPlan(r).presupuesto >= 0, `presupuesto negativo con ${JSON.stringify(r)}`);
  }
});

test("si ya tienes lo que querías, el plan lo sabe", () => {
  const plan = calcularPlan({ ...HOLGADO, ahorroActual: 800, objetivo: 600 });
  assert.equal(plan.falta, 0);
  assert.equal(plan.yaLoTienes, true);
  assert.equal(plan.viable, true, "no puede salir 'inviable' algo que ya está hecho");
});

test("cero meses no rompe la división", () => {
  const plan = calcularPlan({ ...HOLGADO, meses: 0 });
  assert.ok(Number.isFinite(plan.porMes), `${plan.porMes} no es un número`);
});

test("basura en las respuestas no revienta las cuentas", () => {
  const plan = calcularPlan({ ahorroActual: "hola", ingresoMensual: null, gastoMensual: undefined, objetivo: NaN, meses: "x" });
  for (const [k, v] of Object.entries(plan)) {
    if (typeof v === "number") assert.ok(Number.isFinite(v), `${k} salió ${v}`);
  }
});

// ═══ Los avisos, que es donde la app dice la verdad ═════════════════

test("cuando no cabe, lo dice con las dos cifras y sin maquillar", () => {
  const plan = calcularPlan(IMPOSIBLE);
  const avisos = avisosDelPlan(plan, IMPOSIBLE);
  assert.ok(avisos.length >= 2);
  assert.match(avisos[0], /500 €.*20 €/s, "las dos cifras enfrentadas");
  assert.match(avisos[1], /150 meses/, "y cuánto tardaría de verdad");
});

test("gastando más de lo que entra, el aviso va primero al agujero", () => {
  const avisos = avisosDelPlan(calcularPlan(ENROJO), ENROJO);
  assert.match(avisos[0], /60 € más de lo que ingresas/);
  assert.equal(avisos.length, 1, "no se dan consejos de ahorro a quien está en números rojos");
});

test("gastar exactamente lo que entra también se avisa", () => {
  const r = { ...HOLGADO, ingresoMensual: 200, gastoMensual: 200 };
  assert.match(avisosDelPlan(calcularPlan(r), r)[0], /no puedes ahorrar nada/);
});

test("un plan que sale justo avisa igual", () => {
  // 70 de margen, 69 de cuota: sale, pero cualquier imprevisto lo tumba.
  const r = { ...HOLGADO, objetivo: 100 + 69 * 6, meses: 6 };
  const avisos = avisosDelPlan(calcularPlan(r), r);
  assert.ok(avisos.some((a) => /muy justo/.test(a)), avisos.join(" | "));
});

test("un plan holgado no da la brasa con avisos", () => {
  assert.deepEqual(avisosDelPlan(calcularPlan(HOLGADO), HOLGADO), []);
});

// ═══ Cómo va el mes ═════════════════════════════════════════════════

const tx = (dia, importe, categoria = "food", type = "expense") => ({
  date: new Date(2026, 8, dia, 12).toISOString(), amount: importe, category: categoria, type,
});

test("el estado del mes proyecta, no solo suma", () => {
  // Día 10 de un mes de 30, lleva 100 € → acabará sobre 300 €.
  const estado = estadoDelMes([tx(3, 40), tx(7, 60)], 250, new Date(2026, 8, 10, 12));
  assert.equal(estado.gastado, 100);
  assert.equal(estado.proyectado, 300);
  assert.equal(estado.teVasAPasar, true, "300 proyectados con 250 de tope");
});

test("avisar por la proyección y no por lo gastado es el punto", () => {
  // Ha gastado 100 de 250: por lo gastado iría bien. Por el ritmo, no.
  // Avisar el día 28 de que te has pasado no sirve de nada.
  const estado = estadoDelMes([tx(3, 40), tx(7, 60)], 250, new Date(2026, 8, 10, 12));
  assert.ok(estado.disponible > 0, "todavía le queda disponible");
  assert.equal(estado.teVasAPasar, true, "y aun así hay que avisar");
});

test("los movimientos del mes pasado no cuentan", () => {
  const viejo = { date: new Date(2026, 7, 15).toISOString(), amount: 500, category: "food", type: "expense" };
  assert.equal(estadoDelMes([viejo, tx(3, 40)], 250, new Date(2026, 8, 10)).gastado, 40);
});

test("los ingresos no se cuentan como gasto", () => {
  const estado = estadoDelMes([tx(3, 40), tx(5, 200, "salary", "income")], 250, new Date(2026, 8, 10));
  assert.equal(estado.gastado, 40);
  assert.equal(estado.ingresado, 200);
});

test("dice cuánto te queda por día para llegar a fin de mes", () => {
  const estado = estadoDelMes([tx(3, 100)], 250, new Date(2026, 8, 10, 12));
  // Quedan 150 € y 21 días (del 10 al 30 incluidos).
  assert.ok(estado.porDia > 0 && estado.porDia < 10, `${estado.porDia} €/día`);
});

test("sin presupuesto no se inventa que te vas a pasar", () => {
  const estado = estadoDelMes([tx(3, 900)], 0, new Date(2026, 8, 10));
  assert.equal(estado.teVasAPasar, false);
  assert.equal(estado.porDia, null);
});

// ═══ En qué se va el dinero ═════════════════════════════════════════

test("las categorías salen ordenadas de más a menos", () => {
  const cats = porCategoria(
    [tx(2, 30, "food"), tx(3, 50, "leisure"), tx(4, 20, "food"), tx(5, 10, "transport")],
    new Date(2026, 8, 10)
  );
  assert.deepEqual(cats.map((c) => c.id), ["food", "leisure", "transport"]);
  assert.equal(cats[0].importe, 50, "comida: 30 + 20");
});

test("los porcentajes suman aproximadamente cien", () => {
  const cats = porCategoria([tx(2, 30, "food"), tx(3, 50, "leisure"), tx(4, 20, "transport")], new Date(2026, 8, 10));
  const suma = cats.reduce((s, c) => s + c.porcentaje, 0);
  assert.ok(Math.abs(suma - 100) <= 2, `suman ${suma}`);
});

test("una categoría inventada cae en 'otro' en vez de romper la lista", () => {
  const cats = porCategoria([tx(2, 30, "criptomonedas")], new Date(2026, 8, 10));
  assert.equal(cats[0].id, "other");
  assert.ok(cats[0].nombre, "y tiene nombre para pintarla");
});

test("recortable es lo no esencial, y el ahorro no cuenta", () => {
  const cats = porCategoria(
    [tx(2, 90, "food"), tx(3, 50, "leisure"), tx(4, 200, "savings"), tx(5, 30, "shopping")],
    new Date(2026, 8, 10)
  );
  assert.deepEqual(recortables(cats).map((c) => c.id), ["leisure", "shopping"]);
});

// ═══ Apuntar un gasto escribiendo ═══════════════════════════════════
//
// Es el camino del atajo de Apple Pay, y tiene que funcionar SIN IA: en
// la cola del súper con mala cobertura, si dependiera de que la IA
// conteste, fallaría justo cuando hace falta.

test("coma decimal, que es como se escribe en España", () => {
  assert.deepEqual(interpretarGasto("4,20 bocadillo"), { importe: 4.2, categoria: "food", nota: "bocadillo" });
});

test("punto decimal también", () => {
  assert.equal(interpretarGasto("12.50 cine").importe, 12.5);
});

test("el símbolo del euro no estorba, esté donde esté", () => {
  assert.equal(interpretarGasto("3,5€ bus").importe, 3.5);
  assert.equal(interpretarGasto("15 euros zapatillas").importe, 15);
  assert.equal(interpretarGasto("€8 kebab").importe, 8);
});

test("se coge el PRIMER número, no el último", () => {
  // "4,20 bocadillo para 2" es un gasto de 4,20, no de 2.
  assert.equal(interpretarGasto("4,20 bocadillo para 2").importe, 4.2);
});

test("adivina la categoría por palabras que se usan de verdad", () => {
  assert.equal(interpretarGasto("45 mercadona").categoria, "food");
  assert.equal(interpretarGasto("2,40 metro").categoria, "transport");
  assert.equal(interpretarGasto("9,99 spotify").categoria, "leisure");
  assert.equal(interpretarGasto("30 farmacia").categoria, "health");
  assert.equal(interpretarGasto("25 zapatillas").categoria, "shopping");
});

test("si no la adivina, cae en 'otro' en vez de fallar", () => {
  assert.equal(interpretarGasto("17 no sé qué era esto").categoria, "other");
});

test("sin número no se apunta nada, en vez de apuntar cero", () => {
  assert.equal(interpretarGasto("bocadillo"), null);
  assert.equal(interpretarGasto(""), null);
  assert.equal(interpretarGasto(null), null);
  assert.equal(interpretarGasto("0 nada"), null);
});

test("lo que devuelve la IA al clasificar también se acota", () => {
  assert.equal(normalizarGasto({ importe: -5, categoria: "food" }).importe, null);
  assert.equal(normalizarGasto({ importe: 99999999, categoria: "food" }).importe, 100000);
  assert.equal(normalizarGasto({ importe: 4, categoria: "inventada" }).categoria, "other");
  assert.equal(normalizarGasto(null).importe, null);
});

// ═══ El cuestionario y el prompt ════════════════════════════════════

test("no se gasta una llamada con el cuestionario a medias", () => {
  assert.equal(validarRespuestas({ ahorroActual: 0 }).valido, false);
  assert.equal(validarRespuestas(HOLGADO).valido, true);
});

test("un objetivo de cero no vale", () => {
  assert.equal(validarRespuestas({ ...HOLGADO, objetivo: 0 }).valido, false);
});

test("pero tener cero ahorrado sí vale: es el caso normal", () => {
  assert.equal(validarRespuestas({ ...HOLGADO, ahorroActual: 0 }).valido, true);
});

test("todas las preguntas tienen lo que la interfaz necesita", () => {
  for (const p of PREGUNTAS) {
    assert.ok(p.id && p.texto && p.tipo, `${p.id} incompleta`);
    if (p.tipo === "opciones") assert.ok(p.opciones?.length >= 2);
    if (p.tipo === "dinero" || p.tipo === "numero") assert.ok(p.min < p.max);
  }
});

test("al prompt se le dan las cuentas hechas, no los datos crudos", () => {
  // Si la IA tuviera que calcular, calcularía mal. Lo suyo es el consejo.
  const plan = calcularPlan(IMPOSIBLE);
  const texto = promptPlan(IMPOSIBLE, plan, porCategoria([tx(2, 40, "leisure")], new Date(2026, 8, 10)))
    .map((m) => m.content).join("\n");
  assert.match(texto, /NO las recalcules/);
  assert.match(texto, /El plan NO sale/);
  assert.match(texto, /150 meses/);
  assert.match(texto, /Ocio: 40 €/);
});

test("el prompt prohíbe recomendar inversiones", () => {
  // Es una app de ahorro doméstico para un chaval, no un bróker.
  const texto = promptPlan(HOLGADO, calcularPlan(HOLGADO)).map((m) => m.content).join("\n");
  assert.match(texto, /Nunca recomiendas invertir/);
});

test("cada categoría tiene nombre e icono para pintarla", () => {
  for (const [id, c] of Object.entries(CATEGORIAS)) {
    assert.ok(c.nombre && c.icono, `la categoría ${id} está incompleta`);
    assert.equal(typeof c.esencial, "boolean", `${id} no dice si es esencial`);
  }
});
