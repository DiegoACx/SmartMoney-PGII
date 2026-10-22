// ============================================================================
// SmartMoney · Clasificador de movimientos · Modelo (funciones puras)
// ----------------------------------------------------------------------------
// Reproduce EXACTAMENTE el predictor de Python: TF-IDF de n-gramas de
// caracteres (char_wb, 2..5) + regresión logística multinomial, ya entrenado y
// exportado en modelo_clasificador.json.
//
// Este módulo no toca Supabase ni la red: se puede probar con `deno test`.
// ============================================================================

import modeloJson from "./modelo_clasificador.json" with { type: "json" };

export interface CasoPrueba {
  texto: string;
  normalizado: string;
  grupo_id: number;
  probabilidad: number;
}

export interface ModeloClasificador {
  version: string;
  ngram_range: [number, number];
  clases: number[];
  nombres: Record<string, string>;
  ngramas: string[];
  idf: number[];
  coef: number[][];
  intercepto: number[];
  casos_prueba: CasoPrueba[];
}

/** Artefacto entrenado (única fuente de verdad del clasificador). */
export const modelo = modeloJson as unknown as ModeloClasificador;

/**
 * Índice ngrama → columna del vocabulario. Se construye UNA sola vez al cargar
 * el módulo, nunca dentro de predecir().
 */
const INDICE_NGRAMA: Map<string, number> = (() => {
  const indice = new Map<string, number>();
  modelo.ngramas.forEach((ngrama, i) => indice.set(ngrama, i));
  return indice;
})();

/** minúsculas → NFD sin marcas diacríticas → [^a-z0-9]+ a espacio → trim */
export function normalizar(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * N-gramas char_wb: por cada palabra w se analiza " " + w + " "; para cada n
 * entre nmin y nmax, si la palabra acolchada cabe en n se agrega una sola vez y
 * se termina el ciclo, y si no se agregan todos sus n-gramas de tamaño n.
 */
export function ngramasCharWb(t: string, nmin: number, nmax: number): string[] {
  const ngramas: string[] = [];
  for (const w of t.split(" ")) {
    if (w.length === 0) continue;
    const w2 = ` ${w} `;
    for (let n = nmin; n <= nmax; n++) {
      if (w2.length <= n) {
        ngramas.push(w2);
        break;
      }
      for (let i = 0; i <= w2.length - n; i++) {
        ngramas.push(w2.substring(i, i + n));
      }
    }
  }
  return ngramas;
}

/** Conteos de los n-gramas del texto que existen en el vocabulario. */
function contarNgramas(texto: string): Map<number, number> {
  const [nmin, nmax] = modelo.ngram_range;
  const conteos = new Map<number, number>();
  for (const ngrama of ngramasCharWb(texto, nmin, nmax)) {
    const indice = INDICE_NGRAMA.get(ngrama);
    if (indice === undefined) continue;
    conteos.set(indice, (conteos.get(indice) ?? 0) + 1);
  }
  return conteos;
}

/** tf sublineal (1 + ln) × idf, luego normalizado con la norma L2. */
function vectorTfIdf(conteos: Map<number, number>): Map<number, number> {
  const x = new Map<number, number>();
  let sumaCuadrados = 0;
  for (const [i, conteo] of conteos) {
    const valor = (1 + Math.log(conteo)) * modelo.idf[i];
    x.set(i, valor);
    sumaCuadrados += valor * valor;
  }
  const norma = Math.sqrt(sumaCuadrados);
  if (norma > 0) {
    for (const [i, valor] of x) x.set(i, valor / norma);
  }
  return x;
}

/**
 * Probabilidades por clase (en el orden de modelo.clases), o null si el texto
 * queda vacío tras normalizar o no aporta ningún n-grama conocido.
 */
export function probabilidades(texto: string): number[] | null {
  const t = normalizar(texto);
  if (t.length === 0) return null;

  const conteos = contarNgramas(t);
  if (conteos.size === 0) return null;

  const x = vectorTfIdf(conteos);

  // z[k] = intercepto[k] + Σ coef[k][i] × x[i]; solo los índices presentes.
  const z = modelo.intercepto.slice();
  const nClases = modelo.clases.length;
  for (const [i, valor] of x) {
    for (let k = 0; k < nClases; k++) {
      z[k] += modelo.coef[k][i] * valor;
    }
  }

  // softmax estable: se resta el máximo antes de exponenciar.
  const maximo = Math.max(...z);
  let suma = 0;
  const exp = z.map((valor) => {
    const e = Math.exp(valor - maximo);
    suma += e;
    return e;
  });
  return exp.map((e) => e / suma);
}

export interface PrediccionGrupo {
  grupo_id: number;
  confianza: number;
  top3: { grupo_id: number; prob: number }[];
}

/** Grupo más probable con su confianza y los tres grupos con mayor prob. */
export function predecir(texto: string): PrediccionGrupo | null {
  const probs = probabilidades(texto);
  if (probs === null) return null;

  const orden = probs
    .map((prob, k) => ({ k, prob }))
    .sort((a, b) => b.prob - a.prob);

  return {
    grupo_id: modelo.clases[orden[0].k],
    confianza: orden[0].prob,
    top3: orden.slice(0, 3).map(({ k, prob }) => ({
      grupo_id: modelo.clases[k],
      prob,
    })),
  };
}

/** Nombre del grupo según el mapa embebido en el modelo. */
export function nombreGrupo(grupoId: number): string {
  return modelo.nombres[String(grupoId)] ?? `Grupo ${grupoId}`;
}
