// Pruebas de seguridad.js — solo la parte que no toca la red.
//
//   node --test web/
//
// Lo de MFA y el modo de registro no se prueba aquí: son llamadas a
// Supabase, y una prueba con un Supabase de mentira solo comprobaría que
// el Supabase de mentira hace lo que le he dicho. Eso se verifica abriendo
// la app de verdad en un navegador (ver README → Seguridad).

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  problemaContrasena,
  fuerzaContrasena,
  esperaPendiente,
  apuntarFallo,
  limpiarFallos,
  mensajeDeError,
  limpiarCodigo,
} from "./seguridad.js";

// ── Un localStorage de mentira, que es un Map con otro nombre ───────
function almacenFalso() {
  const m = new Map();
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  };
}

// ═══ Contraseñas ════════════════════════════════════════════════════

test("una contraseña corta no pasa", () => {
  assert.match(problemaContrasena("corta1"), /10 caracteres/);
});

test("las contraseñas famosas no pasan, con mayúsculas o sin ellas", () => {
  assert.ok(problemaContrasena("password123"));
  assert.ok(problemaContrasena("PassWord123"));
  assert.ok(problemaContrasena("Habitium123"));
});

test("no se puede meter el correo dentro de la contraseña", () => {
  assert.match(problemaContrasena("rodrigo12345", "rodrigo@correo.com"), /correo/);
  // Pero un usuario de menos de cuatro letras no bloquea nada: si no,
  // quien tenga el correo "ana@…" no podría usar "manzanas" ni nada que
  // lleve "ana" dentro.
  assert.equal(problemaContrasena("ana montaña gris", "ana@correo.com"), null);
});

test("una frase larga y normal sí pasa", () => {
  assert.equal(problemaContrasena("el gato duerme en el tejado", "rodrigo@correo.com"), null);
});

test("repetir una letra o seguir el teclado no cuela", () => {
  assert.ok(problemaContrasena("aaaaaaaaaaaa"));
  assert.ok(problemaContrasena("0123456789abc"));
});

test("una contraseña absurdamente larga tampoco vale", () => {
  // No es una manía: bcrypt y compañía cuestan tiempo de CPU, y mandar
  // contraseñas de megabytes es una forma barata de tumbar el servidor.
  assert.match(problemaContrasena("a1B!".repeat(100)), /demasiado larga/);
});

test("la barrita de fuerza sube con la longitud, no con los símbolos", () => {
  const corta = fuerzaContrasena("Perro123!!", "x@y.com");
  const larga = fuerzaContrasena("el gato duerme en el tejado", "x@y.com");
  assert.ok(larga.nivel > corta.nivel, `${larga.nivel} debería superar a ${corta.nivel}`);
});

test("sin contraseña no se pinta nada", () => {
  assert.deepEqual(fuerzaContrasena(""), { nivel: 0, texto: "" });
});

test("una contraseña que no vale se marca como muy débil, no como vacía", () => {
  assert.equal(fuerzaContrasena("123").nivel, 1);
});

// ═══ El freno a los intentos ════════════════════════════════════════

test("los tres primeros fallos no hacen esperar", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 3; i++) apuntarFallo("uno@correo.com", a, t);
  assert.equal(esperaPendiente("uno@correo.com", a, t), 0);
});

test("a partir del cuarto fallo la espera crece", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 4; i++) apuntarFallo("uno@correo.com", a, t);
  assert.equal(esperaPendiente("uno@correo.com", a, t), 5);

  apuntarFallo("uno@correo.com", a, t);
  assert.equal(esperaPendiente("uno@correo.com", a, t), 15);
});

test("la espera se agota sola con el tiempo", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 4; i++) apuntarFallo("uno@correo.com", a, t);
  assert.equal(esperaPendiente("uno@correo.com", a, t + 6000), 0);
});

test("el freno es por correo: el fallo de uno no castiga al otro", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 6; i++) apuntarFallo("uno@correo.com", a, t);
  assert.ok(esperaPendiente("uno@correo.com", a, t) > 0);
  assert.equal(esperaPendiente("dos@correo.com", a, t), 0);
});

test("da igual cómo escribas las mayúsculas del correo", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 6; i++) apuntarFallo("Uno@Correo.com", a, t);
  assert.ok(esperaPendiente("uno@correo.com", a, t) > 0);
});

test("entrar bien borra el castigo", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 6; i++) apuntarFallo("uno@correo.com", a, t);
  limpiarFallos("uno@correo.com", a);
  assert.equal(esperaPendiente("uno@correo.com", a, t), 0);
});

test("media hora sin fallar reinicia la cuenta desde cero", () => {
  const a = almacenFalso();
  const t = 1_000_000;
  for (let i = 1; i <= 6; i++) apuntarFallo("uno@correo.com", a, t);
  // Vuelve al día siguiente y se equivoca una vez: no debería comerse
  // los cinco minutos de ayer.
  const manana = t + 31 * 60 * 1000;
  apuntarFallo("uno@correo.com", a, manana);
  assert.equal(esperaPendiente("uno@correo.com", a, manana), 0);
});

test("la espera nunca se dispara por encima del último escalón", () => {
  const a = almacenFalso();
  let t = 1_000_000;
  for (let i = 0; i < 40; i++) {
    apuntarFallo("uno@correo.com", a, t);
    t += 10 * 60 * 1000;          // dentro de la media hora, así que acumula
  }
  assert.ok(esperaPendiente("uno@correo.com", a, t) <= 300);
});

test("sin almacenamiento (modo incógnito) no revienta, solo no frena", () => {
  assert.equal(esperaPendiente("uno@correo.com", null, 0), 0);
  assert.doesNotThrow(() => apuntarFallo("uno@correo.com", null, 0));
  assert.doesNotThrow(() => limpiarFallos("uno@correo.com", null));
});

test("un almacenamiento con basura dentro no tumba la app", () => {
  const a = almacenFalso();
  a.setItem("habitium.fallos", "{{{no es json");
  assert.equal(esperaPendiente("uno@correo.com", a, 0), 0);
});

// ═══ Mensajes ═══════════════════════════════════════════════════════

test("el rechazo del portero del registro se traduce", () => {
  assert.match(
    mensajeDeError({ message: 'unexpected_failure: HABITIUM_SIN_INVITACION' }),
    /no está invitado/
  );
});

test("el error genérico de Supabase al rechazar un registro también", () => {
  // Este es el que de verdad llega: GoTrue se traga la excepción del
  // trigger y devuelve su propia frase, que no le dice nada a nadie.
  assert.match(
    mensajeDeError({ message: "Database error saving new user" }),
    /invitación|código/
  );
});

test("al iniciar sesión nunca se dice si el correo existe", () => {
  const m = mensajeDeError({ message: "Invalid login credentials" });
  assert.match(m, /correo o la contraseña/);
  assert.doesNotMatch(m, /no existe|no está registrado/);
});

test("un error que no conocemos se enseña tal cual, no se traga", () => {
  assert.equal(mensajeDeError({ message: "Algo rarísimo" }), "Algo rarísimo");
});

test("un error vacío da una frase, no una cadena en blanco", () => {
  assert.ok(mensajeDeError(null).length > 0);
  assert.ok(mensajeDeError({}).length > 0);
});

// ═══ Códigos de invitación ══════════════════════════════════════════

test("el código se normaliza: mayúsculas y sin sorpresas", () => {
  assert.equal(limpiarCodigo("  habitium-2026 "), "HABITIUM-2026");
});

test("un intento de inyección en el código se queda en nada", () => {
  assert.equal(limpiarCodigo("'; drop table users; --"), "DROPTABLEUSERS--");
  assert.equal(limpiarCodigo("<script>alert(1)</script>"), "SCRIPTALERT1SCRIPT");
});

test("un código kilométrico se corta", () => {
  assert.equal(limpiarCodigo("A".repeat(500)).length, 64);
});

test("sin código, cadena vacía (y no 'undefined')", () => {
  assert.equal(limpiarCodigo(undefined), "");
  assert.equal(limpiarCodigo(null), "");
});
