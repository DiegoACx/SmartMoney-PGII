// ============================================================================
// SmartMoney · Chat IA · montos, porcentajes, periodicidad y plazos
// ----------------------------------------------------------------------------
// Funciones PURAS: leen el texto del usuario y extraen las cifras que necesita
// simular_escenario. No tocan Supabase ni la red (se prueban con `deno test`).
//
// Importante: aquí NO se usa `normalizar` de _shared porque borra "$", "." y
// "%". Se usa `minusculasSinTildes`, que conserva esos símbolos y solo quita
// tildes y mayúsculas.
// ============================================================================

/** Frecuencia con la que se repite un monto. */
export type Periodicidad = "diario" | "semanal" | "quincenal" | "mensual" | "anual";

/** Cuánto vale un monto según su periodicidad, llevado a un mes. */
export const FACTOR_MENSUAL: Record<Periodicidad, number> = {
  diario: 30,
  semanal: 4.345,
  quincenal: 2,
  mensual: 1,
  anual: 1 / 12,
};

/** Un monto ya extraído del mensaje. */
export interface MontoDetectado {
  /** Valor en pesos, sin convertir a mensual. */
  valor: number;
  /** El fragmento tal como apareció ("300 mil", "$1.200.000"…). */
  texto: string;
}

/** Lo que se alcanza a leer de un mensaje para simular un escenario. */
export interface AnalisisMontos {
  montos: MontoDetectado[];
  porcentajes: number[];
  periodicidad: Periodicidad;
  /** Meses desde hoy (hora de Colombia); null si el mensaje no lo dice. */
  plazoMeses: number | null;
}

/** minúsculas + sin tildes, conservando "$", "%", ".", "," y los dígitos. */
export function minusculasSinTildes(texto: string): string {
  return texto
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "");
}

// --- Montos ------------------------------------------------------------------

/** Números escritos con palabras que se aceptan antes de una unidad. */
const PALABRAS_VALOR: Record<string, number> = {
  un: 1,
  uno: 1,
  una: 1,
  medio: 0.5,
  dos: 2,
  tres: 3,
  cuatro: 4,
  cinco: 5,
  seis: 6,
  siete: 7,
  ocho: 8,
  nueve: 9,
  diez: 10,
};

const PALABRAS_NUMERO =
  "un|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|medio";

/** "millones|millon|palo|palo" primero que "mil": son prefijos entre sí. */
const UNIDADES = "millones|millon|palos|palo|lucas|luca|mil|k";

/** Palabras que, tras un número, indican tiempo y no un monto. */
const NO_ES_MONTO =
  "(?:%|(?:por ciento|porciento|mes(?:es)?|anos?|anios?|semanas?|quincenas?|dias?|horas?)\\b)";

/**
 * Tres formas, en orden de prioridad:
 *   1. palabra + unidad  → "un millon", "medio millon", "dos palos";
 *   2. número  + unidad  → "300 mil", "300mil", "300k", "1.5 millones";
 *   3. número suelto     → "$300.000", "300.000" (siempre que no sea un plazo
 *      ni un porcentaje: se descarta si le sigue "%", "mes", "año"…).
 */
const RE_MONTO = new RegExp(
  `\\b(?<palabra>${PALABRAS_NUMERO})\\s+(?<unidad1>${UNIDADES})\\b` +
    `|(?<num>\\d+(?:[.,]\\d+)*)\\s*(?<unidad2>${UNIDADES})\\b` +
    `|(?:\\$\\s*)?(?<plano>\\d+(?:[.,]\\d+)*)(?!\\d)(?!\\s*${NO_ES_MONTO})`,
  "gi",
);

/** Interpreta una cifra colombiana: "." separa miles y "," es decimal. */
export function parsearNumero(token: string): number {
  const t = token.replace(/[^\d.,]/g, "");
  if (t.includes(",")) {
    // "1,5" / "1.234,5": la coma es el separador decimal.
    return Number(t.replace(/\./g, "").replace(",", "."));
  }
  // "300.000" (grupos de 3) son miles; "1.5" (1-2 decimales) es decimal.
  if (/^\d{1,3}(\.\d{3})+$/.test(t)) return Number(t.replace(/\./g, ""));
  if (/^\d+\.\d{1,2}$/.test(t)) return Number(t);
  return Number(t.replace(/\./g, ""));
}

function factorDeUnidad(unidad: string): number {
  return /^(millon|millones|palo|palos)$/.test(unidad) ? 1_000_000 : 1_000;
}

/** Todos los montos en COP del mensaje, en el orden en que aparecen. */
export function extraerMontos(texto: string): MontoDetectado[] {
  const encontrados: MontoDetectado[] = [];
  for (const coincidencia of minusculasSinTildes(texto).matchAll(RE_MONTO)) {
    const grupos = coincidencia.groups ?? {};
    let valor: number;
    if (grupos["palabra"] !== undefined) {
      valor = (PALABRAS_VALOR[grupos["palabra"]] ?? 1) *
        factorDeUnidad(grupos["unidad1"] ?? "");
    } else if (grupos["num"] !== undefined) {
      valor = parsearNumero(grupos["num"]) * factorDeUnidad(grupos["unidad2"] ?? "");
    } else {
      valor = parsearNumero(grupos["plano"] ?? "");
    }
    encontrados.push({ valor, texto: coincidencia[0].trim() });
  }
  return encontrados;
}

// --- Porcentajes -------------------------------------------------------------

const RE_PORCENTAJE = /(\d+(?:[.,]\d+)?)\s*(?:%|por\s*ciento|porciento)/gi;

/** Porcentajes del mensaje ("10%", "10 %", "10 por ciento"). */
export function extraerPorcentajes(texto: string): number[] {
  const valores: number[] = [];
  for (const coincidencia of minusculasSinTildes(texto).matchAll(RE_PORCENTAJE)) {
    valores.push(parsearNumero(coincidencia[1]));
  }
  return valores;
}

// --- Periodicidad ------------------------------------------------------------

const RE_DIARIO = /\bdiari[oa]s?\b|\bal dia\b|\bpor dia\b|\bcada dia\b/;
const RE_QUINCENAL = /\bquincenal(es)?\b|\bquincenas?\b|\bcada quincena\b|\bpor quincena\b/;
const RE_SEMANAL = /\bsemanal(es)?\b|\bsemanas?\b|\bcada semana\b|\bpor semana\b|\ba la semana\b/;
const RE_ANUAL =
  /\banual(es)?\b|\bal ano\b|\bpor ano\b|\bcada ano\b|\banualmente\b/;
const RE_MENSUAL =
  /\bmensual(es)?\b|\bal mes\b|\bpor mes\b|\bcada mes\b|\bmensualmente\b/;

/**
 * Periodicidad con la que se repite el monto. Por defecto 'mensual' (si el
 * mensaje menciona varios periodos gana el más corto: diario > quincenal >
 * semanal > anual > mensual).
 */
export function detectarPeriodicidad(texto: string): Periodicidad {
  const t = minusculasSinTildes(texto);
  if (RE_DIARIO.test(t)) return "diario";
  if (RE_QUINCENAL.test(t)) return "quincenal";
  if (RE_SEMANAL.test(t)) return "semanal";
  if (RE_ANUAL.test(t)) return "anual";
  if (RE_MENSUAL.test(t)) return "mensual";
  return "mensual";
}

/** Lleva un monto a su equivalente mensual según la periodicidad. */
export function aMensual(valor: number, periodicidad: Periodicidad): number {
  return valor * FACTOR_MENSUAL[periodicidad];
}

// --- Plazos ------------------------------------------------------------------

const MESES: Record<string, number> = {
  enero: 1,
  febrero: 2,
  marzo: 3,
  abril: 4,
  mayo: 5,
  junio: 6,
  julio: 7,
  agosto: 8,
  septiembre: 9,
  setiembre: 9,
  octubre: 10,
  noviembre: 11,
  diciembre: 12,
};

const PALABRAS_MESES =
  "un|uno|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce|medio";
const RE_PLAZO = new RegExp(
  `\\b(?:en|dentro de|de aqui a)\\s+` +
    `(\\d+|${PALABRAS_MESES})\\s*(meses|mes|anos|ano|anios|anio)\\b`,
);
// "para diciembre" y también "en diciembre" (así lo escribe la gente).
const RE_PARA_MES =
  /\b(?:para|en)\s+(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)\b/;
const RE_FIN_DE_ANO = /\b(?:a\s+)?fin(?:al)?\s+de\s+ano\b/;

function valorDePalabra(palabra: string): number {
  if (/^\d+$/.test(palabra)) return Number(palabra);
  return PALABRAS_VALOR[palabra] ?? 1;
}

/** Mes mencionado con "para" o "en" ("para diciembre" → "diciembre"), o null. */
export function mesMencionado(texto: string): string | null {
  const coincidencia = minusculasSinTildes(texto).match(RE_PARA_MES);
  return coincidencia ? coincidencia[1] : null;
}

/**
 * Objeto de una compra mencionada ("comprar un portátil" → "portatil"), o null.
 * Se exige el artículo para no confundir el verbo con una preposición
 * ("comprar en diciembre" no produce objeto) ni con un mes.
 */
const RE_OBJETO_COMPRA =
  /\b(?:comprar(?:me|te|nos)?|pagar|adquirir|conseguir)\s+(?:un|una|unos|unas|el|la|los|las|mi|mis|tu|tus|este|esta)\s+([a-z]{3,})/;

export function objetoDeCompra(texto: string): string | null {
  const coincidencia = minusculasSinTildes(texto).match(RE_OBJETO_COMPRA);
  if (coincidencia === null) return null;
  const objeto = coincidencia[1];
  return objeto in MESES ? null : objeto;
}

/** Meses que faltan para el mes indicado (1-12) desde 'YYYY-MM-DD'. */
function mesesHastaMes(hoy: string, mesObjetivo: number): number {
  const mesActual = Number(hoy.slice(5, 7));
  const meses = mesObjetivo - mesActual;
  return meses > 0 ? meses : meses + 12;
}

/** Meses desde hoy hasta la fecha de fin de año. */
function mesesHastaFinDeAno(hoy: string): number {
  const mesActual = Number(hoy.slice(5, 7));
  return Math.max(1, 12 - mesActual);
}

/**
 * Meses desde hoy (hora de Colombia) hasta el plazo mencionado, o null.
 * Reconoce "en 6 meses", "en 3 años", "para diciembre", "en diciembre" y
 * "a fin de año".
 */
export function extraerPlazoMeses(texto: string, hoy: string): number | null {
  const t = minusculasSinTildes(texto);

  if (RE_FIN_DE_ANO.test(t)) return mesesHastaFinDeAno(hoy);

  const paraMes = t.match(RE_PARA_MES);
  if (paraMes) return mesesHastaMes(hoy, MESES[paraMes[1]]);

  const plazo = t.match(RE_PLAZO);
  if (plazo) {
    const cantidad = valorDePalabra(plazo[1]);
    const meses = /^m/.test(plazo[2]) ? cantidad : cantidad * 12;
    return Math.max(0, Math.round(meses));
  }

  return null;
}

// --- Atajo -------------------------------------------------------------------

/** Analiza de una sola vez montos, porcentajes, periodicidad y plazo. */
export function analizarMontos(texto: string, hoy: string): AnalisisMontos {
  return {
    montos: extraerMontos(texto),
    porcentajes: extraerPorcentajes(texto),
    periodicidad: detectarPeriodicidad(texto),
    plazoMeses: extraerPlazoMeses(texto, hoy),
  };
}
