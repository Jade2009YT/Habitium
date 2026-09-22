// Habitium — hablar con la IA desde el navegador.
//
// Hasta ahora la web guardaba tu clave y no la usaba para nada: el
// análisis de fotos solo existía en el iPhone. Esto es el cliente que
// faltaba, y sirve para las tres cosas que necesita Nutrición: el
// cuestionario inicial, reconocer una comida en una foto y recomendarte
// qué comer después.
//
// ── Un aviso que la app también enseña ──────────────────────────────
//
// La clave viaja del navegador a OpenAI/Anthropic directamente, sin
// pasar por ningún servidor nuestro. Eso es bueno (nadie de Habitium ve
// tu clave ni tus comidas) y tiene un precio: la clave está en el
// navegador, así que quien se siente delante de tu equipo desbloqueado
// puede leerla desde las herramientas de desarrollo. La alternativa
// sería un servidor propio que hiciera de intermediario, que es otro
// proyecto entero. La pantalla lo dice en vez de disimularlo.
//
// La Content-Security-Policy ya permite estos dos dominios y solo estos
// dos (`connect-src` en index.html): si mañana se añade otro proveedor,
// hay que añadirlo allí o las peticiones se bloquean en silencio.

const CLAVE_IA = "habitium.aikey";
const PROVEEDOR = "habitium.aiprovider";

/** Modelos por defecto. Se eligen los "mini"/"haiku" a propósito: el
 *  trabajo que hace Habitium —leer un cuestionario, mirar un plato,
 *  sugerir una cena— lo hacen de sobra, y cuestan una fracción. Quien
 *  pague la factura es el dueño de la clave, que es un chaval. */
const MODELOS = {
  openai: "gpt-5-mini",
  anthropic: "claude-haiku-4-5-20251001",
};

export function proveedor() {
  try {
    return localStorage.getItem(PROVEEDOR) || "openai";
  } catch (e) {
    return "openai";
  }
}

/** La clave puede estar en localStorage (tu dispositivo) o en
 *  sessionStorage (el iPad del cole, donde muere al cerrar la pestaña).
 *  Se mira en los dos. */
export function clave(p = proveedor()) {
  for (const almacen of [() => sessionStorage, () => localStorage]) {
    try {
      const valor = almacen().getItem(`${CLAVE_IA}.${p}`);
      if (valor) return valor;
    } catch (e) {}
  }
  return null;
}

export const hayClave = () => Boolean(clave());

/** Un error que la interfaz puede enseñar tal cual. Se distingue de un
 *  fallo cualquiera para poder decir "revisa tu clave" en vez de "error
 *  500", que no le dice nada a nadie. */
export class ErrorIA extends Error {
  constructor(mensaje, { recuperable = true, causa = null } = {}) {
    super(mensaje);
    this.name = "ErrorIA";
    this.recuperable = recuperable;
    this.causa = causa;
  }
}

function traducirFallo(estado, texto) {
  if (estado === 401 || estado === 403) {
    return new ErrorIA("Tu clave no vale o ha caducado. Revísala en Ajustes.", { recuperable: false });
  }
  if (estado === 429) {
    return new ErrorIA("La IA está saturada o has gastado tu cuota. Prueba en un minuto.");
  }
  if (estado === 400 && /image|vision|not support/i.test(texto)) {
    return new ErrorIA("Ese modelo no sabe mirar fotos. Cambia de proveedor en Ajustes.", { recuperable: false });
  }
  if (estado >= 500) {
    return new ErrorIA("La IA está caída ahora mismo. No es cosa tuya.");
  }
  return new ErrorIA(`La IA ha contestado con un error (${estado}).`, { causa: texto });
}

// ── La llamada ──────────────────────────────────────────────────────

/**
 * Manda una conversación y devuelve el texto de la respuesta.
 *
 * `imagen` es un data: URL (lo que da un <input type="file"> leído con
 * FileReader). Se manda tal cual, sin subirla a ningún sitio: va del
 * navegador al proveedor y ahí se queda.
 *
 * `esquema` activa el modo JSON. Se usa siempre que la respuesta tenga
 * que entrar en la app en vez de leerse: pedirle "contesta en JSON" y
 * confiar es lo que hace que un día la app se rompa porque el modelo
 * decidió empezar con "¡Claro! Aquí tienes:".
 */
export async function preguntar(mensajes, { imagen = null, esquema = null, maxTokens = 900 } = {}) {
  const p = proveedor();
  const k = clave(p);
  if (!k) throw new ErrorIA("No hay ninguna clave de IA configurada.", { recuperable: false });

  const señal = AbortSignal.timeout(45000);   // una foto tarda, pero no un minuto

  try {
    const respuesta = p === "anthropic"
      ? await llamarAnthropic(k, mensajes, imagen, esquema, maxTokens, señal)
      : await llamarOpenAI(k, mensajes, imagen, esquema, maxTokens, señal);
    return respuesta;
  } catch (error) {
    if (error instanceof ErrorIA) throw error;
    if (error?.name === "TimeoutError" || error?.name === "AbortError") {
      throw new ErrorIA("La IA ha tardado demasiado. Vuelve a intentarlo.");
    }
    throw new ErrorIA("No se ha podido conectar con la IA. Comprueba internet.", { causa: error });
  }
}

/** Igual que preguntar(), pero devuelve el objeto ya parseado. */
export async function preguntarJSON(mensajes, opciones = {}) {
  const texto = await preguntar(mensajes, { ...opciones, esquema: opciones.esquema ?? true });
  return extraerJSON(texto);
}

/**
 * Saca el objeto de una respuesta que DEBERÍA ser JSON puro y a veces no
 * lo es: los modelos meten ```json ... ``` alrededor, o una frase antes.
 * Recortar hasta las llaves exteriores evita que la app se caiga por eso.
 */
export function extraerJSON(texto) {
  const crudo = String(texto ?? "").trim();
  const intentos = [
    crudo,
    crudo.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""),
    crudo.slice(crudo.indexOf("{"), crudo.lastIndexOf("}") + 1),
  ];
  for (const intento of intentos) {
    if (!intento) continue;
    try {
      const valor = JSON.parse(intento);
      if (valor && typeof valor === "object") return valor;
    } catch (e) {}
  }
  throw new ErrorIA("La IA ha contestado algo que no se entiende. Prueba otra vez.");
}

// ── Cada proveedor a su manera ──────────────────────────────────────

async function llamarOpenAI(k, mensajes, imagen, esquema, maxTokens, signal) {
  const contenido = (m, ultimo) =>
    ultimo && imagen && m.role === "user"
      ? [{ type: "text", text: m.content }, { type: "image_url", image_url: { url: imagen } }]
      : m.content;

  const cuerpo = {
    model: MODELOS.openai,
    messages: mensajes.map((m, i) => ({
      role: m.role,
      content: contenido(m, i === mensajes.length - 1),
    })),
    max_completion_tokens: maxTokens,
  };
  if (esquema) cuerpo.response_format = { type: "json_object" };

  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${k}` },
    body: JSON.stringify(cuerpo),
    signal,
  });
  if (!r.ok) throw traducirFallo(r.status, await r.text().catch(() => ""));

  const datos = await r.json();
  const texto = datos?.choices?.[0]?.message?.content;
  if (!texto) throw new ErrorIA("La IA ha contestado vacío. Prueba otra vez.");
  return texto;
}

async function llamarAnthropic(k, mensajes, imagen, esquema, maxTokens, signal) {
  // Anthropic quiere el "system" fuera de la lista de mensajes, no dentro.
  const sistema = mensajes.filter((m) => m.role === "system").map((m) => m.content).join("\n\n");
  const resto = mensajes.filter((m) => m.role !== "system");

  const contenido = (m, ultimo) => {
    if (!(ultimo && imagen && m.role === "user")) return m.content;
    // Anthropic quiere la imagen troceada: el tipo por un lado y el
    // base64 sin la cabecera "data:image/jpeg;base64," por otro.
    const [cabecera, datos] = String(imagen).split(",");
    const tipo = /data:([^;]+);/.exec(cabecera)?.[1] ?? "image/jpeg";
    return [
      { type: "image", source: { type: "base64", media_type: tipo, data: datos } },
      { type: "text", text: m.content },
    ];
  };

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": k,
      "anthropic-version": "2023-06-01",
      // Sin esto, Anthropic rechaza las peticiones que salen de un
      // navegador. Es una decisión consciente de quien usa su propia
      // clave en su propio equipo, y la app lo explica.
      "anthropic-dangerous-direct-browser-access": "true",
    },
    body: JSON.stringify({
      model: MODELOS.anthropic,
      max_tokens: maxTokens,
      system: sistema || undefined,
      messages: resto.map((m, i) => ({
        role: m.role,
        content: contenido(m, i === resto.length - 1),
      })),
    }),
    signal,
  });
  if (!r.ok) throw traducirFallo(r.status, await r.text().catch(() => ""));

  const datos = await r.json();
  const texto = datos?.content?.find((c) => c.type === "text")?.text;
  if (!texto) throw new ErrorIA("La IA ha contestado vacío. Prueba otra vez.");
  return texto;
}

// ── Fotos ───────────────────────────────────────────────────────────

/**
 * Prepara una foto para mandarla: la encoge y la vuelve a comprimir.
 *
 * No es un capricho de rendimiento. Una foto de un iPhone son 3-4 MB, y
 * mandarla entera cuesta dinero de verdad (se paga por píxel) y tarda
 * varios segundos con datos móviles. A 1024 px de lado largo la IA
 * reconoce un plato exactamente igual de bien.
 */
export function prepararFoto(file, ladoMaximo = 1024, calidad = 0.82) {
  return new Promise((resolve, reject) => {
    const lector = new FileReader();
    lector.onerror = () => reject(new ErrorIA("No se ha podido leer la foto."));
    lector.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new ErrorIA("Ese archivo no parece una foto."));
      img.onload = () => {
        const escala = Math.min(1, ladoMaximo / Math.max(img.width, img.height));
        const lienzo = document.createElement("canvas");
        lienzo.width = Math.round(img.width * escala);
        lienzo.height = Math.round(img.height * escala);
        lienzo.getContext("2d").drawImage(img, 0, 0, lienzo.width, lienzo.height);
        resolve(lienzo.toDataURL("image/jpeg", calidad));
      };
      img.src = lector.result;
    };
    lector.readAsDataURL(file);
  });
}
