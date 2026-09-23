// Habitium — el buzón de ideas.
//
// Aquí quien usa la app escribe qué mejoraría, como una reseña, y los
// demás lo leen y lo votan.
//
// Todo lo que se puede calcular sin tocar la red ni el DOM vive en este
// archivo, para poder probarlo de verdad (sugerencias.test.mjs). La
// interfaz solo pinta lo que esto devuelve.
//
// ── Lo importante de esta sección, y no es la interfaz ──────────────
//
// Es el primer sitio de toda la app donde lo que escribe una persona lo
// lee otra. Eso cambia dos cosas:
//
//   1. Lo que se ve es texto ajeno. Va SIEMPRE escapado al pintarlo, sin
//      excepciones. Un `<img onerror=…>` en el título de una sugerencia
//      se ejecutaría en el navegador de todos los que abran el buzón.
//   2. Las reglas de verdad están en el servidor, no aquí. Lo de este
//      archivo es para avisar antes y no hacerte escribir en balde; si
//      alguien se lo salta abriendo las herramientas del navegador, se
//      topa con las mismas reglas escritas en Postgres. Comprobar dos
//      veces no es duplicar: es que una de las dos no se puede tocar.

/** Lo que cabe en cada campo. Los mismos números que en schema.sql; si
 *  cambian ahí, cambian aquí. La base es la que manda: esto solo sirve
 *  para decírtelo antes de darle a enviar. */
export const LIMITES = {
  titulo: { min: 3, max: 80 },
  texto: { max: 500 },
  nombre: { max: 24 },
  alDia: 5,
};

export const TIPOS = [
  { id: "idea", etiqueta: "Una idea", icono: "💡" },
  { id: "fallo", etiqueta: "Algo que falla", icono: "🐞" },
  { id: "otro", etiqueta: "Otra cosa", icono: "💬" },
];

/** Los estados los pone el que lleva la app, no quien escribe. El orden
 *  de esta lista es el del recorrido de una idea, de recién llegada a
 *  resuelta. */
export const ESTADOS = {
  nueva: { etiqueta: "Nueva", clase: "est-nueva" },
  mirandolo: { etiqueta: "Lo estoy mirando", clase: "est-mirando" },
  en_camino: { etiqueta: "En camino", clase: "est-camino" },
  hecha: { etiqueta: "Hecha", clase: "est-hecha" },
  no: { etiqueta: "No va a ser", clase: "est-no" },
};

export const estadoDe = (status) => ESTADOS[status] ?? ESTADOS.nueva;

// ── Validación ──────────────────────────────────────────────────────

/** Revisa una sugerencia antes de mandarla.
 *
 *  Devuelve los problemas en una lista en vez de parar en el primero: si
 *  te falta el título Y te has pasado de largo en el texto, enterarte de
 *  las dos cosas a la vez es un viaje en lugar de dos.
 */
export function validar({ title = "", body = "", author_name = "", kind = "idea" } = {}) {
  const errores = [];

  // Se recorta antes de medir. Un título de veinte espacios no es un
  // título, y sin esto pasaría el mínimo de tres caracteres.
  const titulo = String(title).trim();
  const texto = String(body).trim();
  const nombre = String(author_name).trim();

  if (titulo.length < LIMITES.titulo.min) {
    errores.push(
      titulo.length === 0
        ? "Ponle un título, aunque sea corto."
        : `El título necesita al menos ${LIMITES.titulo.min} letras.`
    );
  } else if (titulo.length > LIMITES.titulo.max) {
    errores.push(`El título se pasa por ${titulo.length - LIMITES.titulo.max} caracteres.`);
  }

  if (texto.length > LIMITES.texto.max) {
    errores.push(`La explicación se pasa por ${texto.length - LIMITES.texto.max} caracteres.`);
  }

  if (nombre.length > LIMITES.nombre.max) {
    errores.push(`El nombre se pasa por ${nombre.length - LIMITES.nombre.max} caracteres.`);
  }

  if (!TIPOS.some((t) => t.id === kind)) {
    errores.push("Elige si es una idea, un fallo u otra cosa.");
  }

  return {
    ok: errores.length === 0,
    errores,
    // Ya limpio y listo para mandar. Si el nombre viene vacío se firma
    // como Anónimo, que es lo que espera la columna en la base.
    limpio: {
      kind,
      title: titulo,
      body: texto,
      author_name: nombre || "Anónimo",
    },
  };
}

/** Cuántas te quedan hoy.
 *
 *  El límite de verdad lo aplica un disparador en Postgres; esto es para
 *  poder avisarte antes de que escribas un párrafo y te lo rechacen. La
 *  ventana es de 24 horas hacia atrás, no "desde medianoche", porque así
 *  es como cuenta el servidor: si se contara distinto, la app diría que
 *  te queda una y el servidor diría que no.
 */
export function quedanHoy(mias, ahora = new Date()) {
  const desde = ahora.getTime() - 24 * 60 * 60 * 1000;
  const recientes = (mias ?? []).filter((s) => new Date(s.created_at).getTime() > desde).length;
  return Math.max(0, LIMITES.alDia - recientes);
}

// ── Ordenar y filtrar ───────────────────────────────────────────────

export const ORDENES = [
  { id: "votadas", etiqueta: "Más votadas" },
  { id: "nuevas", etiqueta: "Nuevas" },
  { id: "mias", etiqueta: "Las mías" },
];

/**
 * Ordena y filtra el buzón.
 *
 * "Más votadas" desempata por fecha, y no es un detalle: recién abierto
 * el buzón TODO está a cero votos, así que sin desempate el orden sería
 * el que devolviera la base —o sea, ninguno— y la lista bailaría en cada
 * recarga.
 */
export function ordenar(lista, modo = "votadas", miID = null) {
  const items = [...(lista ?? [])];

  if (modo === "mias") {
    return items
      .filter((s) => s.user_id === miID)
      .sort((a, b) => fecha(b) - fecha(a));
  }

  if (modo === "nuevas") {
    return items.sort((a, b) => fecha(b) - fecha(a));
  }

  return items.sort(
    (a, b) => (b.vote_count ?? 0) - (a.vote_count ?? 0) || fecha(b) - fecha(a)
  );
}

const fecha = (s) => new Date(s?.created_at ?? 0).getTime();

/** Las que ya has votado, en un Set para no recorrer la lista de votos
 *  una vez por sugerencia al pintar. */
export function misVotos(votos, miID) {
  return new Set(
    (votos ?? []).filter((v) => v.user_id === miID).map((v) => v.suggestion_id)
  );
}

// ── Cómo se cuenta el tiempo ────────────────────────────────────────

/** "hace 2 h", "hace 3 días". Sin librerías y sin segundos: a nadie le
 *  importa que una sugerencia tenga 47 segundos. */
export function haceCuanto(cuando, ahora = new Date()) {
  const min = Math.floor((ahora.getTime() - new Date(cuando).getTime()) / 60000);

  // Los relojes de dos aparatos nunca coinciden del todo. Sin esto, algo
  // escrito hace diez segundos desde otro móvil puede salir "hace -1 min".
  if (min < 1) return "ahora mismo";
  if (min < 60) return `hace ${min} min`;

  const horas = Math.floor(min / 60);
  if (horas < 24) return `hace ${horas} h`;

  const dias = Math.floor(horas / 24);
  if (dias === 1) return "ayer";
  if (dias < 30) return `hace ${dias} días`;

  const meses = Math.floor(dias / 30);
  return meses === 1 ? "hace un mes" : `hace ${meses} meses`;
}

// ── Cómo se resume el buzón ─────────────────────────────────────────

/** El titular de arriba del todo: cuántas hay y cuántas están hechas.
 *  Ver que algo pedido acabó hecho es lo único que hace que la gente
 *  vuelva a escribir. */
export function resumen(lista) {
  const items = lista ?? [];
  return {
    total: items.length,
    hechas: items.filter((s) => s.status === "hecha").length,
    enCamino: items.filter((s) => s.status === "en_camino" || s.status === "mirandolo").length,
  };
}
