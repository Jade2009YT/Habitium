// Habitium — el plan de ahorro, con las cuentas hechas de verdad.
//
// ── Lo mismo que en Nutrición, por la misma razón ───────────────────
//
// Al entrar en Finanzas por primera vez te pregunta cuánto tienes,
// cuánto te entra, cuánto quieres ahorrar y para cuándo. Y con eso monta
// el plan.
//
// Pero el número no sale de la IA sin filtro. Aquí el peligro no es la
// salud, es peor de lo que parece: una app que te dice "sí, puedes
// ahorrar 300 € al mes" cuando te entran 200 no te está ayudando, te
// está preparando para fallar en enero y dejarlo. La aritmética no
// opina, así que la aritmética manda:
//
//   · La FÓRMULA calcula: cuánto hay que apartar al mes, si llegas a
//     tiempo, cuánto te queda para gastar, y si el objetivo es imposible.
//   · La IA aporta lo que una fórmula no puede: dónde recortar mirando
//     TUS categorías, y una meta alternativa cuando la tuya no cabe.
//
// Todo lo de aquí es función pura y está probado (finanzas-ia.test.mjs).

export const CATEGORIAS = {
  food: { nombre: "Comida", icono: "🍔", esencial: true },
  transport: { nombre: "Transporte", icono: "🚌", esencial: true },
  health: { nombre: "Salud", icono: "💊", esencial: true },
  services: { nombre: "Servicios", icono: "📱", esencial: true },
  leisure: { nombre: "Ocio", icono: "🎮", esencial: false },
  shopping: { nombre: "Compras", icono: "🛍️", esencial: false },
  savings: { nombre: "Ahorro", icono: "🏦", esencial: false },
  salary: { nombre: "Ingresos", icono: "💼", esencial: false },
  other: { nombre: "Otro", icono: "•", esencial: false },
};

// ═══ El cuestionario ════════════════════════════════════════════════

export const PREGUNTAS = [
  {
    id: "ahorroActual",
    texto: "¿Cuánto tienes ahorrado ahora mismo?",
    ayuda: "Todo junto: banco, hucha, lo que sea. Si no tienes nada, pon 0.",
    tipo: "dinero", min: 0, max: 1000000,
  },
  {
    id: "ingresoMensual",
    texto: "¿Cuánto dinero te entra al mes?",
    ayuda: "Paga, trabajo, clases particulares… lo que entre de forma más o menos fija.",
    tipo: "dinero", min: 0, max: 100000,
  },
  {
    id: "gastoMensual",
    texto: "¿Y cuánto se te va al mes, más o menos?",
    ayuda: "A ojo vale. Habitium lo irá ajustando solo según apuntes gastos.",
    tipo: "dinero", min: 0, max: 100000,
  },
  {
    id: "meta",
    texto: "¿Para qué quieres ahorrar?",
    tipo: "opciones",
    opciones: [
      { valor: "colchon", etiqueta: "Tener un colchón por si acaso", icono: "🛟" },
      { valor: "compra", etiqueta: "Comprarme algo concreto", icono: "🎯" },
      { valor: "viaje", etiqueta: "Un viaje", icono: "✈️" },
      { valor: "sinmas", etiqueta: "Ahorrar sin más", icono: "🏦" },
    ],
  },
  {
    id: "objetivo",
    texto: "¿Cuánto quieres llegar a tener?",
    ayuda: "La cifra a la que quieres llegar, contando lo que ya tienes.",
    tipo: "dinero", min: 1, max: 1000000,
  },
  {
    id: "meses",
    texto: "¿En cuántos meses?",
    tipo: "numero", unidad: "meses", min: 1, max: 120, paso: 1,
  },
  {
    id: "notas",
    texto: "¿Algo más que deba saber?",
    ayuda: "Que en verano no cobras, que pagas el gimnasio, lo que sea. Puedes dejarlo en blanco.",
    tipo: "texto", opcional: true,
  },
];

export function validarRespuestas(respuestas) {
  const faltan = [];
  for (const p of PREGUNTAS) {
    if (p.opcional) continue;
    const valor = respuestas?.[p.id];
    if (valor === undefined || valor === null || valor === "") { faltan.push(p.id); continue; }
    if (p.tipo === "dinero" || p.tipo === "numero") {
      const n = Number(valor);
      if (!Number.isFinite(n) || n < p.min || n > p.max) faltan.push(p.id);
    }
    if (p.tipo === "opciones" && !p.opciones.some((o) => o.valor === valor)) faltan.push(p.id);
  }
  return { valido: faltan.length === 0, faltan };
}

// ═══ Las cuentas ════════════════════════════════════════════════════

/**
 * El plan. Todo sale de restar y dividir, y por eso no se discute.
 *
 * `viable` es la palabra clave: dice si el objetivo cabe en lo que te
 * sobra cada mes. Cuando no cabe, la app NO lo maquilla — propone la
 * cifra que sí sale y dice cuánto tardarías con tu ritmo real.
 */
export function calcularPlan(r) {
  const ahorroActual = Number(r.ahorroActual) || 0;
  const ingreso = Number(r.ingresoMensual) || 0;
  const gasto = Number(r.gastoMensual) || 0;
  const objetivo = Number(r.objetivo) || 0;
  const meses = Math.max(1, Math.round(Number(r.meses) || 1));

  const falta = Math.max(0, objetivo - ahorroActual);
  const margen = ingreso - gasto;                  // lo que te sobra al mes
  const porMes = falta / meses;                    // lo que haría falta apartar

  // Con margen cero o negativo no hay plan que valga: primero hay que
  // gastar menos. Dividir entre un número negativo daría "llegas en -4
  // meses", que es la clase de mentira matemática que hace que una app
  // parezca rota.
  const mesesReales = margen > 0 ? Math.ceil(falta / margen) : null;

  const viable = margen > 0 && porMes <= margen;
  const yaLoTienes = falta === 0;

  return {
    ahorroActual,
    objetivo,
    falta,
    meses,
    margen,
    porMes: Math.round(porMes * 100) / 100,
    mesesReales,
    viable: viable || yaLoTienes,
    yaLoTienes,
    // El presupuesto del mes: lo que te puedes gastar apartando lo del
    // plan. Si el plan no es viable, se aparta lo que se pueda.
    presupuesto: Math.max(0, Math.round((ingreso - Math.min(porMes, Math.max(0, margen))) * 100) / 100),
    // Cuánto habría que apartar para que SÍ salga en el plazo pedido.
    // Es lo que se enseña cuando no es viable.
    necesarioPorMes: Math.round(porMes * 100) / 100,
  };
}

/** El aviso en cristiano de por qué un plan no sale. Va antes que
 *  cualquier consejo de la IA: si las cuentas no dan, lo primero es
 *  decirlo, no adornarlo. */
export function avisosDelPlan(plan, r) {
  const avisos = [];
  const eur = (n) => `${Math.round(n * 100) / 100} €`;

  if (plan.yaLoTienes) {
    avisos.push("Ya tienes lo que querías ahorrar. Puedes subir el objetivo o dejarlo aquí.");
    return avisos;
  }

  if (plan.margen <= 0) {
    avisos.push(
      plan.margen === 0
        ? "Gastas exactamente lo que ingresas, así que ahora mismo no puedes ahorrar nada. Lo primero no es el objetivo: es recortar algo."
        : `Gastas ${eur(-plan.margen)} más de lo que ingresas cada mes. Antes de ahorrar hay que tapar ese agujero.`
    );
    return avisos;
  }

  if (!plan.viable) {
    avisos.push(
      `Para llegar a ${eur(plan.objetivo)} en ${plan.meses} ${plan.meses === 1 ? "mes" : "meses"} ` +
      `harían falta ${eur(plan.necesarioPorMes)} al mes, y solo te sobran ${eur(plan.margen)}.`
    );
    avisos.push(
      `Con tu ritmo real llegarías en ${plan.mesesReales} ${plan.mesesReales === 1 ? "mes" : "meses"}. ` +
      `Si quieres mantener el plazo, hay que gastar ${eur(plan.necesarioPorMes - plan.margen)} menos al mes.`
    );
  }

  if (plan.viable && plan.porMes > plan.margen * 0.9) {
    avisos.push("El plan sale, pero muy justo: cualquier imprevisto te lo tumba. Plantéate un mes más de plazo.");
  }

  return avisos;
}

/** Cómo va el mes: cuánto llevas gastado y si vas a tiempo.
 *
 *  `ritmo` es lo que de verdad se mira en el día 12 del mes: no "has
 *  gastado 140 €" sino "a este ritmo acabas el mes en 350 €". */
export function estadoDelMes(transacciones, presupuesto, ahora = new Date()) {
  const inicio = new Date(ahora.getFullYear(), ahora.getMonth(), 1);
  const diasDelMes = new Date(ahora.getFullYear(), ahora.getMonth() + 1, 0).getDate();
  const diaDeHoy = ahora.getDate();

  const delMes = (transacciones ?? []).filter((t) => new Date(t.date) >= inicio);
  const gastado = delMes.filter((t) => t.type === "expense").reduce((s, t) => s + Number(t.amount || 0), 0);
  const ingresado = delMes.filter((t) => t.type === "income").reduce((s, t) => s + Number(t.amount || 0), 0);

  const proyectado = diaDeHoy > 0 ? (gastado / diaDeHoy) * diasDelMes : 0;
  const limite = Number(presupuesto) || 0;

  return {
    gastado: Math.round(gastado * 100) / 100,
    ingresado: Math.round(ingresado * 100) / 100,
    disponible: Math.round((limite - gastado) * 100) / 100,
    proyectado: Math.round(proyectado * 100) / 100,
    // "Vas a pasarte" se decide por la proyección, no por lo gastado:
    // avisar el día 28 de que te has pasado no sirve de nada.
    teVasAPasar: limite > 0 && proyectado > limite * 1.05,
    diaDeHoy,
    diasDelMes,
    porDia: limite > 0 ? Math.round(((limite - gastado) / Math.max(1, diasDelMes - diaDeHoy + 1)) * 100) / 100 : null,
  };
}

/** El gasto por categoría del mes, ordenado de más a menos. Es la
 *  sección de "en qué se me va el dinero". */
export function porCategoria(transacciones, ahora = new Date()) {
  const inicio = new Date(ahora.getFullYear(), ahora.getMonth(), 1);
  const suma = new Map();

  for (const t of transacciones ?? []) {
    if (t.type !== "expense") continue;
    if (new Date(t.date) < inicio) continue;
    const cat = CATEGORIAS[t.category] ? t.category : "other";
    suma.set(cat, (suma.get(cat) ?? 0) + Number(t.amount || 0));
  }

  const total = [...suma.values()].reduce((a, b) => a + b, 0);
  return [...suma.entries()]
    .map(([id, importe]) => ({
      id,
      ...CATEGORIAS[id],
      importe: Math.round(importe * 100) / 100,
      porcentaje: total > 0 ? Math.round((importe / total) * 100) : 0,
    }))
    .sort((a, b) => b.importe - a.importe);
}

/** Dónde se puede recortar de verdad: lo no esencial, de mayor a menor.
 *  Es lo que se le pasa a la IA para que no invente. */
export function recortables(categorias) {
  return categorias.filter((c) => !c.esencial && c.id !== "savings" && c.importe > 0);
}

// ═══ Lo que se le dice a la IA ══════════════════════════════════════

const SISTEMA = `Eres el asesor de Habitium, una app que usa gente joven en España.
Hablas en español de España, en segunda persona, directo y sin sermones.
Hablas de euros. Nunca inventas cifras: usas solo las que te dan.
Nunca recomiendas invertir, ni criptomonedas, ni productos financieros: esto es ahorro doméstico.
Contestas SIEMPRE en JSON válido y nada más: sin texto antes ni después, sin markdown.`;

export function promptPlan(respuestas, plan, categorias = []) {
  const gastos = categorias.length
    ? categorias.map((c) => `${c.nombre}: ${c.importe} € (${c.porcentaje}%)`).join(", ")
    : "todavía no hay gastos apuntados";

  return [
    { role: "system", content: SISTEMA },
    {
      role: "user",
      content: `Comenta este plan de ahorro. Las cuentas ya están hechas: NO las recalcules ni las discutas.

Situación:
- Tiene ahorrados: ${plan.ahorroActual} €
- Le entran: ${respuestas.ingresoMensual} € al mes
- Se le van: ${respuestas.gastoMensual} € al mes
- Le sobran: ${plan.margen} € al mes
- Quiere llegar a: ${plan.objetivo} € en ${plan.meses} meses (para: ${respuestas.meta})
- Haría falta apartar: ${plan.necesarioPorMes} € al mes
- ¿Sale?: ${plan.viable ? "sí" : "NO"}${plan.mesesReales ? ` (a su ritmo real llegaría en ${plan.mesesReales} meses)` : ""}
- En qué se le va el dinero este mes: ${gastos}
- Notas suyas: ${respuestas.notas || "ninguna"}

${plan.viable
  ? "El plan sale. Dile por qué va bien y dale UN consejo concreto para no salirse."
  : "El plan NO sale. No lo maquilles: dile claramente que con esos números no llega, y propón qué cambiar — o el plazo, o el objetivo, o un recorte concreto de sus categorías."}

Devuelve exactamente este JSON:
{
  "resumen": "dos o tres frases sobre su situación, en segunda persona",
  "consejo": "UN consejo concreto y accionable, con una cifra si puede ser. Una o dos frases.",
  "recorte": "de qué categoría suya recortaría y cuánto, o cadena vacía si no hace falta"
}`,
    },
  ];
}

/** Clasificar un gasto escrito a mano. Se usa para que apuntar un gasto
 *  desde Atajos sea escribir "4,20 bocadillo" y ya. */
export function promptClasificar(texto) {
  return [
    { role: "system", content: SISTEMA },
    {
      role: "user",
      content: `Clasifica este gasto: "${String(texto).slice(0, 200)}"

Categorías posibles: ${Object.entries(CATEGORIAS).map(([id, c]) => `${id} (${c.nombre})`).join(", ")}

Devuelve exactamente este JSON:
{ "importe": número en euros, "categoria": "una de las de arriba", "nota": "descripción corta" }`,
    },
  ];
}

/** Normaliza lo que devuelve la IA al clasificar. Un importe negativo o
 *  absurdo se descarta: es mejor no apuntar nada que apuntar basura. */
export function normalizarGasto(bruto) {
  const importe = Number(bruto?.importe);
  return {
    importe: Number.isFinite(importe) && importe > 0 ? Math.min(Math.round(importe * 100) / 100, 100000) : null,
    categoria: CATEGORIAS[bruto?.categoria] ? bruto.categoria : "other",
    nota: String(bruto?.nota ?? "").slice(0, 120),
  };
}

/**
 * Interpreta un gasto escrito a mano SIN IA: "4,20 bocadillo",
 * "12 euros cine", "3,5€ bus".
 *
 * Existe porque el camino rápido tiene que funcionar siempre: si el
 * atajo de Apple Pay dependiera de que la IA conteste, apuntar un gasto
 * en la cola del súper con mala cobertura fallaría justo cuando hace
 * falta. La IA mejora la categoría; esto garantiza que el número entra.
 */
export function interpretarGasto(texto) {
  const crudo = String(texto ?? "").trim();
  if (!crudo) return null;

  // Coma o punto decimal, con o sin símbolo pegado. Se coge el PRIMER
  // número: "4,20 bocadillo para 2" es un gasto de 4,20, no de 2.
  const m = /(\d+(?:[.,]\d{1,2})?)/.exec(crudo);
  if (!m) return null;
  const importe = Number(m[1].replace(",", "."));
  if (!Number.isFinite(importe) || importe <= 0) return null;

  const resto = crudo
    .replace(m[0], " ")
    .replace(/(?:€|eur(?:os?)?|euros?)/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  // Una tabla corta de palabras que salen de verdad. No pretende ser
  // completa: si no acierta, cae en "other" y la IA lo afina luego.
  const PISTAS = {
    food: /bocadi|desayun|comi|cena|menú|menu|super|mercadona|lidl|carrefour|restaurante|bar |café|cafe|pizza|kebab|hamburgues/i,
    transport: /bus|metro|tren|taxi|uber|cabify|gasolina|bici|patinete|billete|abono/i,
    leisure: /cine|concierto|videojueg|juego|netflix|spotify|salir|fiesta|discoteca|bolera/i,
    shopping: /ropa|zapatil|camiseta|amazon|regalo|zara|compra/i,
    health: /farmacia|médic|medico|dentista|gimnasio|gym/i,
    services: /móvil|movil|teléfono|telefono|internet|luz|agua|suscrip/i,
  };

  let categoria = "other";
  for (const [id, patron] of Object.entries(PISTAS)) {
    if (patron.test(resto)) { categoria = id; break; }
  }

  return { importe, categoria, nota: resto.slice(0, 120) };
}
