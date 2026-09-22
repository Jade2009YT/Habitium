// Habitium — el objetivo diario, decidido con la IA pero no POR la IA.
//
// ── Por qué este archivo existe ─────────────────────────────────────
//
// Lo pedido era: "el objetivo diario de nutrición lo decide la IA". Y
// tiene sentido — un número sacado de una tabla genérica no sirve igual
// para alguien de 16 años que juega al fútbol tres días que para alguien
// que está sentado todo el día.
//
// Pero hay una línea que no se puede cruzar. Esto es una app de salud
// que va a usar un adolescente, y un modelo de lenguaje puede devolver
// 900 kcal por un error de formato, porque el usuario escribió algo raro
// en el cuestionario, o porque le pidió "quiero adelgazar rápido". Si la
// app se traga ese número y se lo pone como objetivo diario, la app está
// empujando a alguien a comer la mitad de lo que su cuerpo necesita solo
// para seguir funcionando.
//
// Así que aquí el reparto es:
//
//   · La IA DECIDE: el reparto de macros, el ritmo, los consejos, el tono
//     y los matices que una fórmula no puede tener en cuenta.
//   · La fórmula ACOTA: se calcula el metabolismo basal con Mifflin-St
//     Jeor (la más usada y validada en clínica) y el gasto diario, y la
//     propuesta de la IA tiene que caer dentro de un rango razonable
//     alrededor de eso. Si se sale, se recorta y la app lo dice.
//
// El suelo duro es el metabolismo basal: las calorías que gasta el
// cuerpo estando tumbado sin hacer nada. Por debajo de eso no se baja
// nunca, diga lo que diga nadie.
//
// Todo lo de aquí es función pura y está probado (nutricion-ia.test.mjs).

// ═══ El cuestionario ════════════════════════════════════════════════
//
// Son pocas preguntas a propósito: lo que de verdad mueve el número es
// peso, altura, edad, sexo y actividad. Preguntar quince cosas hace que
// la gente abandone a la tercera.

export const PREGUNTAS = [
  {
    id: "objetivo",
    texto: "¿Qué quieres conseguir?",
    tipo: "opciones",
    opciones: [
      { valor: "perder", etiqueta: "Perder grasa", icono: "📉" },
      { valor: "mantener", etiqueta: "Mantenerme igual", icono: "⚖️" },
      { valor: "ganar", etiqueta: "Ganar músculo", icono: "💪" },
    ],
  },
  {
    id: "sexo",
    texto: "¿Sexo biológico?",
    ayuda: "Solo se usa para la fórmula del metabolismo: hombres y mujeres gastan distinto en reposo.",
    tipo: "opciones",
    opciones: [
      { valor: "hombre", etiqueta: "Hombre", icono: "♂️" },
      { valor: "mujer", etiqueta: "Mujer", icono: "♀️" },
    ],
  },
  { id: "edad", texto: "¿Cuántos años tienes?", tipo: "numero", unidad: "años", min: 10, max: 100, paso: 1 },
  { id: "altura", texto: "¿Cuánto mides?", tipo: "numero", unidad: "cm", min: 120, max: 220, paso: 1 },
  { id: "peso", texto: "¿Cuánto pesas ahora?", tipo: "numero", unidad: "kg", min: 30, max: 250, paso: 0.5 },
  {
    id: "actividad",
    texto: "¿Cuánto te mueves en una semana normal?",
    tipo: "opciones",
    opciones: [
      { valor: "sedentario", etiqueta: "Poco: clase y casa", icono: "🪑" },
      { valor: "ligero", etiqueta: "Ando bastante o entreno 1-2 días", icono: "🚶" },
      { valor: "moderado", etiqueta: "Entreno 3-4 días", icono: "🏃" },
      { valor: "alto", etiqueta: "Entreno 5-6 días", icono: "🏋️" },
      { valor: "atleta", etiqueta: "Todos los días, y en serio", icono: "🔥" },
    ],
  },
  {
    id: "notas",
    texto: "¿Algo más que deba saber?",
    ayuda: "Alergias, si eres vegetariano, si no desayunas, lo que sea. Puedes dejarlo en blanco.",
    tipo: "texto",
    opcional: true,
  },
];

/** Los factores de actividad estándar sobre el metabolismo basal. */
const FACTOR_ACTIVIDAD = {
  sedentario: 1.2,
  ligero: 1.375,
  moderado: 1.55,
  alto: 1.725,
  atleta: 1.9,
};

/** Cuánto se ajusta según el objetivo. Un 15% es un déficit o superávit
 *  sostenible; los "20 kilos en un mes" de internet son justo lo que
 *  hace que la gente lo deje o se haga daño. */
const AJUSTE_OBJETIVO = { perder: -0.15, mantener: 0, ganar: 0.12 };

// ═══ La fórmula ═════════════════════════════════════════════════════

/** Metabolismo basal (Mifflin-St Jeor). Lo que gasta el cuerpo tumbado
 *  sin hacer nada: es el suelo absoluto. */
export function metabolismoBasal({ sexo, peso, altura, edad }) {
  const base = 10 * Number(peso) + 6.25 * Number(altura) - 5 * Number(edad);
  return Math.round(base + (sexo === "mujer" ? -161 : 5));
}

/** Gasto diario: el basal por lo que te mueves. */
export function gastoDiario(respuestas) {
  const factor = FACTOR_ACTIVIDAD[respuestas.actividad] ?? FACTOR_ACTIVIDAD.ligero;
  return Math.round(metabolismoBasal(respuestas) * factor);
}

/** El objetivo que sale de la fórmula, sin IA de por medio. Es el punto
 *  de referencia contra el que se compara lo que proponga la IA, y el
 *  respaldo si la IA no está disponible. */
export function objetivoDeReferencia(respuestas) {
  const gasto = gastoDiario(respuestas);
  const ajuste = AJUSTE_OBJETIVO[respuestas.objetivo] ?? 0;
  const basal = metabolismoBasal(respuestas);

  // El déficit nunca baja del basal, aunque el porcentaje lo pidiera.
  const calorias = Math.max(basal, Math.round(gasto * (1 + ajuste)));

  // Proteína por kilo de peso, que es como se calcula de verdad —
  // repartir por porcentaje de calorías da números absurdos en los
  // extremos. Grasa al 25% de las calorías (el mínimo sano ronda el
  // 20%), y el resto a carbohidratos.
  const proteinaPorKg = respuestas.objetivo === "ganar" ? 1.8 : respuestas.objetivo === "perder" ? 2.0 : 1.6;
  const proteina = Math.round(Number(respuestas.peso) * proteinaPorKg);
  const grasa = Math.round((calorias * 0.25) / 9);
  const carbos = Math.max(0, Math.round((calorias - proteina * 4 - grasa * 9) / 4));

  return { calorias, proteina, carbos, grasa };
}

// ═══ El cerrojo ═════════════════════════════════════════════════════

/**
 * Acota lo que ha propuesto la IA. Devuelve el objetivo final y la lista
 * de correcciones, para que la app pueda decirlas en vez de cambiar el
 * número a escondidas.
 *
 * Los límites:
 *   · Calorías: nunca por debajo del metabolismo basal, nunca por encima
 *     del doble del gasto diario.
 *   · Proteína: entre 0,8 y 3 g por kilo. Por debajo no se mantiene
 *     músculo; por encima no aporta nada y carga los riñones.
 *   · Grasa: al menos el 15% de las calorías. Es la que hace que
 *     funcionen las hormonas, y es la primera que la gente recorta.
 *   · Y los macros tienen que sumar aproximadamente las calorías: si la
 *     IA da cuatro números que no cuadran entre sí, se recalculan los
 *     carbohidratos, que son el cajón de sastre.
 */
export function acotarObjetivo(propuesta, respuestas) {
  const basal = metabolismoBasal(respuestas);
  const gasto = gastoDiario(respuestas);
  const peso = Number(respuestas.peso);
  const avisos = [];

  const num = (valor, porDefecto) => {
    const n = Number(valor);
    return Number.isFinite(n) && n > 0 ? n : porDefecto;
  };

  const referencia = objetivoDeReferencia(respuestas);
  let calorias = Math.round(num(propuesta?.calorias, referencia.calorias));
  let proteina = Math.round(num(propuesta?.proteina, referencia.proteina));
  let grasa = Math.round(num(propuesta?.grasa, referencia.grasa));
  let carbos = Math.round(num(propuesta?.carbos, referencia.carbos));

  // ── Calorías ──
  if (calorias < basal) {
    avisos.push(`La IA proponía ${calorias} kcal, por debajo de lo que tu cuerpo gasta en reposo (${basal}). Se ha subido a ${basal}.`);
    calorias = basal;
  }
  const techo = gasto * 2;
  if (calorias > techo) {
    avisos.push(`La IA proponía ${calorias} kcal, más del doble de tu gasto diario. Se ha bajado a ${Math.round(techo)}.`);
    calorias = Math.round(techo);
  }

  // ── Proteína ──
  const proteinaMin = Math.round(peso * 0.8);
  const proteinaMax = Math.round(peso * 3);
  if (proteina < proteinaMin) {
    avisos.push(`Proteína demasiado baja (${proteina} g). Subida al mínimo razonable: ${proteinaMin} g.`);
    proteina = proteinaMin;
  } else if (proteina > proteinaMax) {
    avisos.push(`Proteína demasiado alta (${proteina} g). Bajada a ${proteinaMax} g.`);
    proteina = proteinaMax;
  }

  // ── Grasa ──
  const grasaMin = Math.round((calorias * 0.15) / 9);
  if (grasa < grasaMin) {
    avisos.push(`Grasa demasiado baja (${grasa} g): hace falta para las hormonas. Subida a ${grasaMin} g.`);
    grasa = grasaMin;
  }

  // ── Que los macros cuadren con las calorías ──
  const deLosMacros = proteina * 4 + carbos * 4 + grasa * 9;
  if (Math.abs(deLosMacros - calorias) > calorias * 0.1) {
    const nuevos = Math.max(0, Math.round((calorias - proteina * 4 - grasa * 9) / 4));
    avisos.push(`Los macros no sumaban las calorías (${deLosMacros} frente a ${calorias}). Carbohidratos recalculados: ${nuevos} g.`);
    carbos = nuevos;
  }

  return { objetivo: { calorias, proteina, carbos, grasa }, avisos };
}

/** ¿Está el cuestionario completo y con valores creíbles? Se comprueba
 *  ANTES de gastar una llamada a la IA. */
export function validarRespuestas(respuestas) {
  const faltan = [];
  for (const p of PREGUNTAS) {
    if (p.opcional) continue;
    const valor = respuestas?.[p.id];
    if (valor === undefined || valor === null || valor === "") { faltan.push(p.id); continue; }
    if (p.tipo === "numero") {
      const n = Number(valor);
      if (!Number.isFinite(n) || n < p.min || n > p.max) faltan.push(p.id);
    }
    if (p.tipo === "opciones" && !p.opciones.some((o) => o.valor === valor)) faltan.push(p.id);
  }
  return { valido: faltan.length === 0, faltan };
}

// ═══ Lo que se le dice a la IA ══════════════════════════════════════

const SISTEMA = `Eres el nutricionista de Habitium, una app que usa gente joven en España.
Hablas en español de España, en segunda persona, claro y sin paternalismo.
Nunca prometes resultados rápidos ni recomiendas dietas agresivas.
Si alguien te pide un déficit extremo, le explicas por qué no y propones algo sostenible.
Contestas SIEMPRE en JSON válido y nada más: sin texto antes ni después, sin markdown.`;

export function promptObjetivo(respuestas) {
  const referencia = objetivoDeReferencia(respuestas);
  const basal = metabolismoBasal(respuestas);
  const gasto = gastoDiario(respuestas);

  return [
    { role: "system", content: SISTEMA },
    {
      role: "user",
      content: `Calcula el objetivo diario de esta persona.

Datos:
- Objetivo: ${respuestas.objetivo}
- Sexo biológico: ${respuestas.sexo}
- Edad: ${respuestas.edad} años
- Altura: ${respuestas.altura} cm
- Peso: ${respuestas.peso} kg
- Actividad: ${respuestas.actividad}
- Notas: ${respuestas.notas || "ninguna"}

Referencia calculada con Mifflin-St Jeor (úsala como punto de partida, ajústala si las notas lo justifican):
- Metabolismo basal: ${basal} kcal
- Gasto diario estimado: ${gasto} kcal
- Objetivo de referencia: ${referencia.calorias} kcal · ${referencia.proteina} g proteína · ${referencia.carbos} g carbohidratos · ${referencia.grasa} g grasa

Devuelve exactamente este JSON:
{
  "calorias": número entero,
  "proteina": gramos enteros,
  "carbos": gramos enteros,
  "grasa": gramos enteros,
  "explicacion": "dos o tres frases explicando POR QUÉ estos números, en segunda persona",
  "consejo": "un consejo concreto y accionable para esta persona, una frase"
}`,
    },
  ];
}

export function promptFoto() {
  return [
    { role: "system", content: SISTEMA },
    {
      role: "user",
      content: `Mira esta foto de comida y estima lo que hay.

Sé realista con las cantidades: estima el tamaño de la ración por lo que se ve en el plato.
Si no distingues bien qué es, dilo en "confianza" en vez de inventar.

Devuelve exactamente este JSON:
{
  "nombre": "nombre corto del plato, como lo diría una persona",
  "calorias": número entero,
  "proteina": gramos enteros,
  "carbos": gramos enteros,
  "grasa": gramos enteros,
  "confianza": "alta" | "media" | "baja",
  "nota": "qué has visto y qué has supuesto sobre la cantidad, una frase"
}`,
    },
  ];
}

/**
 * Qué comer después. La gracia está en lo que se le pasa: lo que YA has
 * comido hoy y lo que te queda de objetivo. Sin eso, la respuesta sería
 * un consejo genérico de internet.
 */
export function promptRecomendacion({ objetivo, consumido, momento, respuestas, comidasDeHoy = [] }) {
  const queda = {
    calorias: Math.max(0, objetivo.calorias - consumido.calorias),
    proteina: Math.max(0, objetivo.proteina - consumido.proteina),
    carbos: Math.max(0, objetivo.carbos - consumido.carbos),
    grasa: Math.max(0, objetivo.grasa - consumido.grasa),
  };

  return [
    { role: "system", content: SISTEMA },
    {
      role: "user",
      content: `Recomienda qué comer ahora.

Momento del día: ${momento}
Ya ha comido hoy: ${comidasDeHoy.length ? comidasDeHoy.join(", ") : "nada todavía"}
Lleva consumido: ${consumido.calorias} kcal · ${consumido.proteina} g P · ${consumido.carbos} g C · ${consumido.grasa} g G
Le queda hasta su objetivo: ${queda.calorias} kcal · ${queda.proteina} g P · ${queda.carbos} g C · ${queda.grasa} g G
Notas de la persona: ${respuestas?.notas || "ninguna"}

Son comidas de casa, en España, de alguien joven que no es cocinero.
Nada de ingredientes raros ni de recetas de veinte minutos.
Si ya ha llegado a su objetivo, dilo y propón algo ligero o nada.

Devuelve exactamente este JSON:
{
  "titulo": "qué comer, en pocas palabras",
  "porque": "por qué esto y no otra cosa, mirando lo que le queda. Una o dos frases.",
  "calorias": número entero aproximado,
  "proteina": gramos enteros,
  "alternativa": "otra opción en pocas palabras, por si no le apetece la primera"
}`,
    },
  ];
}

/** La franja del día, para pedir una recomendación que tenga sentido.
 *  Con horarios españoles: aquí se come a las tres y se cena a las diez. */
export function momentoDelDia(fecha = new Date()) {
  const h = fecha.getHours();
  if (h < 11) return "desayuno";
  if (h < 13) return "almuerzo de media mañana";
  if (h < 16) return "comida";
  if (h < 20) return "merienda";
  if (h < 24) return "cena";
  return "algo antes de dormir";
}

/** Normaliza lo que devuelve la IA al analizar una foto. Los números
 *  negativos o absurdos se recortan: una foto de un plato no son 9000
 *  kcal, y si la IA lo dice es que se ha equivocado. */
export function normalizarComida(bruto) {
  const num = (v, max) => {
    const n = Math.round(Number(v));
    return Number.isFinite(n) && n >= 0 ? Math.min(n, max) : 0;
  };
  return {
    nombre: String(bruto?.nombre ?? "Comida").slice(0, 120),
    calorias: num(bruto?.calorias, 5000),
    proteina: num(bruto?.proteina, 500),
    carbos: num(bruto?.carbos, 800),
    grasa: num(bruto?.grasa, 400),
    confianza: ["alta", "media", "baja"].includes(bruto?.confianza) ? bruto.confianza : "media",
    nota: String(bruto?.nota ?? "").slice(0, 300),
  };
}
