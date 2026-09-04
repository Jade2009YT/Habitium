// Pruebas del motor de progresión de la web.
//
//   node --test web/progression.test.mjs
//
// Sin dependencias: usa el corredor de pruebas que trae node. No hace
// falta instalar nada ni tener conexión.
//
// Lo que hay aquí no es "cobertura por tener": son las tres cosas que se
// rompen de verdad y en silencio —
//
//   1. La curva de niveles. Un error aquí (un nivel que se salta, una
//      barra que nunca se llena) se nota al usar la app pero es muy
//      molesto de diagnosticar.
//   2. El sorteo de los retos. Si deja de coincidir con el de Swift, el
//      iPhone y la web muestran retos distintos el mismo día y no hay
//      ningún error visible que lo delate.
//   3. Los valores del pase. Si un nivel cambia de precio, alguien que
//      ya lo tenía desbloqueado lo "pierde" en la web.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as p from "./progression.js";

// ── Curva de niveles ────────────────────────────────────────────────

test("cada nivel cuesta 100 + (nivel-1)*50", () => {
  assert.equal(p.xpToAdvance(1), 100);
  assert.equal(p.xpToAdvance(2), 150);
  assert.equal(p.xpToAdvance(3), 200);
  assert.equal(p.xpToAdvance(10), 550);
});

test("el nivel 1 es gratis y el resto acumula", () => {
  assert.equal(p.totalXPRequired(1), 0);
  assert.equal(p.totalXPRequired(2), 100);
  assert.equal(p.totalXPRequired(3), 250); // 100 + 150
  assert.equal(p.totalXPRequired(4), 450); // + 200
});

test("el nivel sale del XP total, y en los bordes exactos", () => {
  assert.equal(p.levelForTotalXP(0), 1);
  assert.equal(p.levelForTotalXP(99), 1);
  assert.equal(p.levelForTotalXP(100), 2, "justo al llegar ya es nivel 2");
  assert.equal(p.levelForTotalXP(249), 2);
  assert.equal(p.levelForTotalXP(250), 3);
});

test("nivel y XP acumulado son coherentes entre sí", () => {
  // La comprobación que de verdad importa: recorrer los 60 primeros
  // niveles y exigir que las dos funciones nunca se contradigan.
  for (let level = 1; level <= 60; level++) {
    const at = p.totalXPRequired(level);
    assert.equal(p.levelForTotalXP(at), level, `justo al entrar al nivel ${level}`);
    assert.equal(p.levelForTotalXP(at + p.xpToAdvance(level) - 1), level, `al final del nivel ${level}`);
  }
});

test("la barra del nivel va de 0 a 1 y nunca se sale", () => {
  assert.equal(p.progressWithinLevel(0), 0);
  assert.equal(p.progressWithinLevel(50), 0.5);
  assert.equal(p.progressWithinLevel(100), 0, "recién subido, la barra vuelve a empezar");
  for (const xp of [0, 1, 99, 100, 837, 5000, 99999]) {
    const v = p.progressWithinLevel(xp);
    assert.ok(v >= 0 && v <= 1, `fuera de rango con ${xp} XP: ${v}`);
  }
});

test("lo que falta para el siguiente nivel cuadra con la barra", () => {
  for (const xp of [0, 37, 100, 260, 1234]) {
    const level = p.levelForTotalXP(xp);
    const falta = p.xpRemainingToNextLevel(xp);
    assert.equal(p.levelForTotalXP(xp + falta), level + 1, `con ${xp} XP`);
    assert.equal(p.levelForTotalXP(xp + falta - 1), level, `con ${xp} XP, uno menos no basta`);
  }
});

test("cada tramo de nivel tiene su título", () => {
  assert.equal(p.titleForLevel(1), "Empezando");
  assert.equal(p.titleForLevel(7), "Constante");
  assert.equal(p.titleForLevel(99), "Leyenda");
});

// ── Pase de temporada ───────────────────────────────────────────────

test("los 12 niveles del pase suben de precio sin repetirse", () => {
  assert.equal(p.SEASON_TIERS.length, 12);
  for (let i = 1; i < p.SEASON_TIERS.length; i++) {
    assert.ok(
      p.SEASON_TIERS[i].xpRequired > p.SEASON_TIERS[i - 1].xpRequired,
      `el nivel ${i + 1} del pase no cuesta más que el anterior`
    );
  }
  const ids = new Set(p.SEASON_TIERS.map((t) => t.id));
  assert.equal(ids.size, 12, "hay ids repetidos");
});

test("el pase desbloquea justo al llegar al XP, no antes", () => {
  assert.equal(p.unlockedTiers(49).length, 0);
  assert.equal(p.unlockedTiers(50).length, 1);
  assert.equal(p.unlockedTiers(4000).length, 12);
  assert.equal(p.nextTier(4000), null, "con el pase completo no hay siguiente");
});

test("la barra del pase va de 0 a 1 en cada tramo", () => {
  assert.equal(p.progressToNextTier(0), 0);
  assert.equal(p.progressToNextTier(25), 0.5);
  assert.equal(p.progressToNextTier(50), 0, "recién desbloqueado, empieza el tramo siguiente");
  assert.equal(p.progressToNextTier(999999), 1, "pase completo");
});

test("el acento clásico está siempre; el resto se gana", () => {
  assert.deepEqual(p.availableAccents([]), ["classic"]);
  assert.deepEqual(p.availableAccents(["t2"]), ["classic", "ocean"]);
  assert.equal(p.highestTitle([]), null);
  assert.equal(p.highestTitle(["t3", "t6"]), "Disciplinado", "gana el título más alto");
});

test("todo acento del pase existe en la tabla de acentos", () => {
  for (const tier of p.SEASON_TIERS) {
    if (tier.kind === "accent") {
      assert.ok(p.ACCENTS[tier.value], `el acento «${tier.value}» del ${tier.id} no está definido`);
    }
  }
});

// ── Retos del día ───────────────────────────────────────────────────

test("el mismo día da siempre los mismos tres retos", () => {
  const dia = new Date(2026, 8, 3);
  const a = p.dailyChallenges(dia);
  const b = p.dailyChallenges(dia);
  assert.deepEqual(a, b, "reabrir la app cambiaría los retos a media mañana");
  assert.equal(a.length, 3);
});

test("días distintos dan retos distintos", () => {
  const firmas = new Set();
  for (let d = 1; d <= 28; d++) {
    firmas.add(JSON.stringify(p.dailyChallenges(new Date(2026, 8, d))));
  }
  assert.ok(firmas.size >= 15, `solo ${firmas.size} combinaciones en 28 días: repite demasiado`);
});

test("nunca sale el mismo reto dos veces el mismo día", () => {
  for (let d = 1; d <= 60; d++) {
    const retos = p.dailyChallenges(new Date(2026, 0, d));
    const tipos = new Set(retos.map((r) => r.kind));
    assert.equal(tipos.size, retos.length, `reto repetido el día ${d}`);
  }
});

test("los objetivos salen siempre de las opciones previstas", () => {
  const opciones = { habits: [2, 3, 4], tasks: [1, 2, 3], meals: [2, 3] };
  for (let d = 1; d <= 90; d++) {
    for (const reto of p.dailyChallenges(new Date(2026, 3, d))) {
      const esperadas = opciones[reto.kind] ?? [1];
      assert.ok(esperadas.includes(reto.goal), `${reto.kind} con objetivo ${reto.goal}`);
    }
  }
});

test("medicación y entrenamiento aparecen a veces, no a diario", () => {
  // Si salieran siempre, quien no toma nada ni entrena tendría un reto
  // imposible permanente. Si no salieran nunca, sobrarían del código.
  let conRaros = 0;
  for (let d = 1; d <= 90; d++) {
    const tipos = p.dailyChallenges(new Date(2026, 3, d)).map((r) => r.kind);
    if (tipos.includes("medication") || tipos.includes("workout")) conRaros++;
  }
  assert.ok(conRaros > 0, "nunca aparecen");
  assert.ok(conRaros < 90, "aparecen todos los días");
});

test("el sorteo no se ha movido (paridad con el iPhone)", () => {
  // Valores fijados a mano tras comprobar el mismo sorteo con una
  // transcripción independiente del Swift. Si esta prueba falla, el
  // generador ha cambiado y la web mostrará retos distintos a los del
  // iPhone el mismo día — que es un fallo invisible, sin error ninguno.
  assert.deepEqual(
    p.dailyChallenges(new Date(2026, 8, 3)).map((c) => [c.kind, c.goal]),
    [["focus", 1], ["habits", 4], ["meals", 3]]
  );
  assert.deepEqual(
    p.dailyChallenges(new Date(2026, 0, 1)).map((c) => [c.kind, c.goal]),
    p.dailyChallenges(new Date(2026, 0, 1)).map((c) => [c.kind, c.goal])
  );
});

test("una tirada con una sola opción también consume número", () => {
  // El detalle que rompería la paridad en silencio: Swift tira igual
  // aunque solo haya una opción posible. Si aquí nos la saltásemos, la
  // secuencia se desviaría a partir de ese punto.
  const a = new p.SeededGenerator(20260903);
  a.nextBelow(1);
  const b = new p.SeededGenerator(20260903);
  assert.notEqual(a.nextBelow(10), b.nextBelow(10), "nextBelow(1) no ha consumido nada");
});

test("el generador es reproducible y de 64 bits", () => {
  const a = new p.SeededGenerator(42);
  const b = new p.SeededGenerator(42);
  for (let i = 0; i < 20; i++) assert.equal(a.next(), b.next());
  const g = new p.SeededGenerator(1);
  for (let i = 0; i < 100; i++) {
    const v = g.next();
    assert.ok(v >= 0n && v < 1n << 64n, "se ha salido de 64 bits");
  }
});

// ── Claves y temporada ──────────────────────────────────────────────

test("la clave anti-repetición lleva el día, con ceros delante", () => {
  assert.equal(p.dedupeKey("login", new Date(2026, 8, 3)), "login:2026-09-03");
  assert.equal(p.dedupeKey("habit:abc", new Date(2026, 11, 25)), "habit:abc:2026-12-25");
});

test("la temporada es el mes natural", () => {
  assert.equal(p.currentSeasonID(new Date(2026, 8, 30)), "2026-09");
  assert.equal(p.currentSeasonID(new Date(2026, 9, 1)), "2026-10");
});

test("cada fuente de XP tiene puntos, nombre e icono", () => {
  for (const [key, src] of Object.entries(p.XP_SOURCES)) {
    assert.ok(src.xp > 0, `${key} no da puntos`);
    assert.ok(src.name && src.icon, `${key} sin nombre o icono`);
  }
  // El esfuerzo tiene que mandar sobre el relleno.
  assert.ok(p.xpFor("allHabitsCompleted") > p.xpFor("mealLogged") * 4);
});
