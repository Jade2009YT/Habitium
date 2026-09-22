// Habitium — la parte de seguridad que vive en el navegador.
//
// Importante entender qué hace cada mitad, porque es fácil confundirse:
//
//   · El SERVIDOR (supabase/schema.sql) es quien DECIDE. Row Level
//     Security, el portero del registro, los límites de tamaño. Eso no se
//     puede saltar: aunque alguien reescriba esta app entera desde las
//     herramientas del navegador, el servidor sigue diciendo que no.
//
//   · Esto de aquí AYUDA. Avisa antes de que el servidor tenga que decir
//     que no, frena los intentos a lo bruto y pone la verificación en dos
//     pasos al alcance de un botón. Nada de lo que hay en este archivo es
//     la última línea de defensa, y está escrito sabiéndolo.
//
// Todo lo que no necesita red son funciones puras, para poder probarlas
// de verdad (ver seguridad.test.mjs).

// ═══ Contraseñas ════════════════════════════════════════════════════

/** Las que salen siempre las primeras en un ataque automático, en
 *  español y en inglés. No es una lista completa —no existe— es una red
 *  para que nadie use LA obvia. Solo van las de 10+ caracteres: las
 *  cortas ya las corta el mínimo de longitud. */
export const CONTRASENAS_MALAS = new Set([
  "contrasena1", "contraseña1", "contrasena123", "contraseña123",
  "1234567890", "0123456789", "12345678910", "1234512345", "123456789a",
  "qwertyuiop", "qwerty12345", "asdfghjkl1",
  "password12", "password123", "passw0rd123", "iloveyou12", "iloveyou123",
  "administrador", "habitium123", "aaaaaaaaaa", "abcdefghij",
  "principiante", "megustaelfutbol", "futbolista1", "teamocariño",
]);

/** Devuelve el motivo por el que una contraseña no vale, o null si vale.
 *
 *  Diez caracteres y NADA de "una mayúscula, un número y un símbolo".
 *  Esas reglas suenan serias pero empujan a la gente a poner
 *  "Contraseña1!" —que está entre las primeras que prueba cualquier
 *  ataque— mientras que cada carácter de más multiplica de verdad el
 *  tiempo que cuesta romperla. */
export function problemaContrasena(password, email = "") {
  const p = String(password ?? "");
  if (p.length < 10) return "La contraseña necesita al menos 10 caracteres.";
  if (p.length > 200) return "Esa contraseña es demasiado larga (máximo 200).";
  if (CONTRASENAS_MALAS.has(p.toLowerCase())) {
    return "Esa contraseña está entre las más usadas del mundo. Pon otra.";
  }
  const usuario = String(email ?? "").split("@")[0].toLowerCase();
  if (usuario.length >= 4 && p.toLowerCase().includes(usuario)) {
    return "No uses tu correo dentro de la contraseña.";
  }
  if (/^(.)\1+$/.test(p)) return "Repetir la misma letra no es una contraseña.";
  if (/^(0123456789|1234567890|abcdefghij)/.test(p.toLowerCase())) {
    return "Eso es una secuencia del teclado, no una contraseña.";
  }
  return null;
}

/** De 0 a 4, para pintar la barrita mientras se escribe. No es una
 *  medida científica de entropía: es una señal honesta de "esto está
 *  flojo" / "esto está bien" que la gente entiende de un vistazo. */
export function fuerzaContrasena(password, email = "") {
  const p = String(password ?? "");
  if (!p) return { nivel: 0, texto: "" };
  if (problemaContrasena(p, email)) return { nivel: 1, texto: "Muy débil" };

  let puntos = 0;
  if (p.length >= 12) puntos++;
  if (p.length >= 16) puntos++;
  if (/[a-zA-Z]/.test(p) && /[0-9]/.test(p)) puntos++;
  if (/[^a-zA-Z0-9]/.test(p) || / /.test(p)) puntos++;
  if (new Set(p).size >= 10) puntos++;

  if (puntos <= 1) return { nivel: 2, texto: "Justita" };
  if (puntos <= 3) return { nivel: 3, texto: "Bien" };
  return { nivel: 4, texto: "Muy buena" };
}

// ═══ Freno a los intentos a lo bruto ════════════════════════════════
//
// Supabase ya limita los intentos por su cuenta, pero lo hace por IP y con
// un margen amplio. Esto frena antes y, sobre todo, frena EN EL
// DISPOSITIVO: en el iPad compartido del instituto, quien se ponga a
// probar contraseñas de otro se come la espera en su propia cara.
//
// No protege contra alguien que ataque el servidor directamente —para eso
// están el límite de Supabase y la verificación en dos pasos— pero sí
// contra el caso realista: alguien con tu móvil en la mano.

const CLAVE_FALLOS = "habitium.fallos";
// Segundos de espera según cuántas veces seguidas se haya fallado. El
// índice es el número de fallo, así que el hueco 0 nunca se usa.
// Los tres primeros salen gratis: equivocarse al teclear la contraseña
// dos o tres veces es lo más normal del mundo, y castigar eso solo
// molesta a quien sí es el dueño de la cuenta.
const ESPERAS = [0, 0, 0, 0, 5, 15, 45, 120, 300];

function leerFallos(almacen) {
  try {
    return JSON.parse(almacen.getItem(CLAVE_FALLOS) ?? "{}") || {};
  } catch (e) {
    return {};
  }
}

function guardarFallos(almacen, datos) {
  try {
    almacen.setItem(CLAVE_FALLOS, JSON.stringify(datos));
  } catch (e) {
    /* modo incógnito o almacenamiento lleno: se pierde el freno, no la app */
  }
}

/** Segundos que faltan para poder volver a intentarlo. 0 = adelante. */
export function esperaPendiente(email, almacen = globalThis.localStorage, ahora = Date.now()) {
  if (!almacen) return 0;
  const clave = String(email ?? "").toLowerCase();
  const registro = leerFallos(almacen)[clave];
  if (!registro) return 0;
  const espera = ESPERAS[Math.min(registro.n, ESPERAS.length - 1)] * 1000;
  const restante = registro.t + espera - ahora;
  return restante > 0 ? Math.ceil(restante / 1000) : 0;
}

export function apuntarFallo(email, almacen = globalThis.localStorage, ahora = Date.now()) {
  if (!almacen) return;
  const clave = String(email ?? "").toLowerCase();
  const datos = leerFallos(almacen);
  const previo = datos[clave];

  // Media hora sin fallar borra la cuenta: el que se equivoca hoy y vuelve
  // mañana no arrastra el castigo de ayer.
  const n = previo && ahora - previo.t < 30 * 60 * 1000 ? previo.n + 1 : 1;
  datos[clave] = { n, t: ahora };
  guardarFallos(almacen, datos);
}

export function limpiarFallos(email, almacen = globalThis.localStorage) {
  if (!almacen) return;
  const datos = leerFallos(almacen);
  delete datos[String(email ?? "").toLowerCase()];
  guardarFallos(almacen, datos);
}

// ═══ Mensajes de error en cristiano ═════════════════════════════════
//
// Los errores que devuelve el servidor están en inglés y algunos son
// directamente crípticos: cuando el portero del registro rechaza a
// alguien, Supabase contesta "Database error saving new user", que no le
// dice nada a nadie. Aquí se traducen.
//
// Ojo con una cosa: en el inicio de sesión NUNCA se distingue entre
// "ese correo no existe" y "la contraseña no es esa". Decirlo sería
// regalar una forma de averiguar qué correos tienen cuenta.

const TRADUCCIONES = [
  [/HABITIUM_REGISTRO_CERRADO/i, "El registro está cerrado ahora mismo."],
  [/HABITIUM_SIN_INVITACION/i, "Ese correo no está invitado y el código no vale. Pide una invitación."],
  [/HABITIUM_INVITACION_CADUCADA/i, "Esa invitación ya ha caducado."],
  [/HABITIUM_INVITACION_AGOTADA/i, "Ese código de invitación ya se ha usado del todo."],
  [/HABITIUM_LIMITE_FILAS/i, "Has llegado al máximo de datos guardados en esa sección."],
  [/database error saving new user/i, "No se ha podido crear la cuenta: comprueba la invitación o el código."],
  [/invalid login credentials/i, "El correo o la contraseña no son correctos."],
  [/email not confirmed/i, "Todavía no has confirmado el correo. Mira tu bandeja de entrada."],
  [/user already registered|already been registered/i, "Ya hay una cuenta con ese correo. Prueba a iniciar sesión."],
  [/email rate limit|over_email_send_rate_limit/i, "Se han enviado demasiados correos seguidos. Espera unos minutos."],
  [/for security purposes|rate limit|too many requests/i, "Demasiados intentos seguidos. Espera un momento y vuelve a probar."],
  [/invalid totp|invalid code|mfa.*invalid|factor.*invalid/i, "Ese código no es válido. Mira la app del móvil otra vez."],
  [/challenge.*expired|code.*expired/i, "El código ha caducado. Pide uno nuevo en tu app."],
  [/password.*at least|weak.?password/i, "La contraseña es demasiado corta o demasiado común."],
  [/failed to fetch|network|load failed/i, "Sin conexión con el servidor. Comprueba internet."],
  [/violates check constraint/i, "Ese texto es demasiado largo. Acórtalo un poco."],
];

export function mensajeDeError(error) {
  const texto = String(error?.message ?? error?.hint ?? error ?? "").trim();
  if (!texto) return "Algo ha ido mal. Vuelve a intentarlo.";
  for (const [patron, mensaje] of TRADUCCIONES) {
    if (patron.test(texto)) return mensaje;
  }
  return texto;
}

// ═══ Cerrar sesión sola en un dispositivo prestado ══════════════════
//
// El caso real: el iPad del instituto. Marcas "este no es mi dispositivo",
// la sesión ya vive en sessionStorage (muere al cerrar la pestaña), pero
// si te levantas y la dejas abierta, el siguiente se sienta delante de tus
// datos. Veinte minutos sin tocar nada y fuera.

export function vigilarInactividad(minutos, alExpirar, ventana = globalThis) {
  const limite = minutos * 60 * 1000;
  let reloj = null;

  const reiniciar = () => {
    if (reloj) clearTimeout(reloj);
    reloj = setTimeout(alExpirar, limite);
  };

  const eventos = ["pointerdown", "keydown", "visibilitychange", "focus"];
  for (const e of eventos) ventana.addEventListener(e, reiniciar, { passive: true });
  reiniciar();

  return () => {
    if (reloj) clearTimeout(reloj);
    for (const e of eventos) ventana.removeEventListener(e, reiniciar);
  };
}

// ═══ Verificación en dos pasos (TOTP) ═══════════════════════════════
//
// Es LA medida contra el robo de cuentas. Con ella puesta, saber tu
// contraseña no basta: hace falta además el móvil que tiene el código de
// seis cifras que cambia cada treinta segundos.
//
// Supabase lo trae de serie, y lo mejor: el código QR que devuelve ya
// viene dibujado (un SVG), así que no hay que cargar ninguna librería de
// fuera — y eso significa que la Content-Security-Policy no se toca.

/** Los factores que esta cuenta tiene dados de alta y confirmados. */
export async function factoresActivos(supabase) {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  return (data?.totp ?? []).filter((f) => f.status === "verified");
}

/** ¿Está la sesión a medias? Es decir: la contraseña ya está puesta pero
 *  falta el código del móvil.
 *
 *  `nextLevel === 'aal2'` quiere decir "esta cuenta tiene segundo factor".
 *  `currentLevel` dice por dónde va la sesión ahora. Si no coinciden, hay
 *  que pedir el código ANTES de enseñar ningún dato. */
export async function faltaSegundoFactor(supabase) {
  const { data, error } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (error) return false;   // ante la duda no se deja a nadie fuera de su app
  return data?.nextLevel === "aal2" && data?.currentLevel !== "aal2";
}

/** Empieza el alta: devuelve el QR listo para pintar y el código de
 *  respaldo por si el móvil no lee el QR. Todavía NO está activado —
 *  hace falta confirmarlo con un código, para asegurarse de que el móvil
 *  de verdad lo ha guardado. Si no, la gente se quedaría fuera de su
 *  propia cuenta. */
export async function empezarAltaMFA(supabase) {
  const { data, error } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: `Habitium ${new Date().toISOString().slice(0, 16)}`,
  });
  if (error) throw error;
  return {
    factorId: data.id,
    qr: data.totp?.qr_code ?? "",
    secreto: data.totp?.secret ?? "",
  };
}

/** Confirma el alta con el primer código. A partir de aquí, entrar exige
 *  el móvil. */
export async function confirmarAltaMFA(supabase, factorId, codigo) {
  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId,
    code: String(codigo).replace(/\D/g, ""),
  });
  if (error) throw error;
}

/** El código que se pide al entrar. */
export async function verificarSegundoFactor(supabase, codigo) {
  const factores = await factoresActivos(supabase);
  if (!factores.length) throw new Error("No hay ningún método de verificación activo.");
  const { error } = await supabase.auth.mfa.challengeAndVerify({
    factorId: factores[0].id,
    code: String(codigo).replace(/\D/g, ""),
  });
  if (error) throw error;
}

export async function quitarMFA(supabase, factorId) {
  const { error } = await supabase.auth.mfa.unenroll({ factorId });
  if (error) throw error;
}

// ═══ Modo de registro ═══════════════════════════════════════════════
//
// Se pregunta al servidor si se puede crear cuenta y en qué condiciones.
// La función del servidor SOLO dice el modo: nunca confirma si un correo
// concreto está o no invitado, porque eso convertiría la app en una
// máquina de averiguar correos válidos.

let modoRecordado = null;

export async function modoDeRegistro(supabase) {
  if (modoRecordado) return modoRecordado;
  try {
    const { data, error } = await supabase.rpc("signup_mode");
    if (error) throw error;
    modoRecordado = data ?? "abierto";
  } catch (e) {
    // La función aún no existe (esquema sin actualizar) o no hay red:
    // se asume abierto y que decida el servidor al intentarlo. Fallar
    // hacia "cerrado" dejaría la app inservible por un despiste.
    modoRecordado = "abierto";
  }
  return modoRecordado;
}

/** Un código de invitación es corto y sin sorpresas: letras, números y
 *  guiones. Recortarlo aquí evita mandar basura al servidor. */
export function limpiarCodigo(valor) {
  return String(valor ?? "").trim().toUpperCase().replace(/[^A-Z0-9-]/g, "").slice(0, 64);
}
