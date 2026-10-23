// ============================================================================
// SmartMoney · Clasificador genérico de n-gramas de caracteres
// ----------------------------------------------------------------------------
// Reproduce EXACTAMENTE el predictor de Python: TF-IDF de n-gramas de caracteres
// (char_wb, 2..5) + regresión logística multinomial, a partir de cualquier
// artefacto JSON con este formato:
//
//   { version, ngram_range:[nmin,nmax], clases:[...], nombres:{}, ngramas:[],
//     idf:[], coef:[][], intercepto:[], casos_prueba:[...] }
//
// Lo usan clasificar-movimiento (13 grupos de gasto) y chat-ia (6 intenciones),
// cada uno con su propio JSON. Este módulo no toca Supabase ni la red: se puede
// probar con `deno test`.
// ============================================================================

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

export interface PrediccionGrupo {
  grupo_id: number;
  confianza: number;
  top3: { grupo_id: number; prob: number }[];
}

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

/**
 * Predictor ya entrenado. El índice ngrama → columna del vocabulario se
 * construye UNA sola vez en el constructor, nunca dentro de predecir().
 */
export class ClasificadorNgramas {
  readonly modelo: ModeloClasificador;
  private readonly indice: Map<string, number>;

  constructor(modelo: ModeloClasificador) {
    this.modelo = modelo;
    this.indice = new Map<string, number>();
    modelo.ngramas.forEach((ngrama, i) => this.indice.set(ngrama, i));
  }

  /** Conteos de los n-gramas del texto que existen en el vocabulario. */
  private contarNgramas(texto: string): Map<number, number> {
    const [nmin, nmax] = this.modelo.ngram_range;
    const conteos = new Map<number, number>();
    for (const ngrama of ngramasCharWb(texto, nmin, nmax)) {
      const indice = this.indice.get(ngrama);
      if (indice === undefined) continue;
      conteos.set(indice, (conteos.get(indice) ?? 0) + 1);
    }
    return conteos;
  }

  /** tf sublineal (1 + ln) × idf, luego normalizado con la norma L2. */
  private vectorTfIdf(conteos: Map<number, number>): Map<number, number> {
    const modelo = this.modelo;
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
  probabilidades(texto: string): number[] | null {
    const modelo = this.modelo;
    const t = normalizar(texto);
    if (t.length === 0) return null;

    const conteos = this.contarNgramas(t);
    if (conteos.size === 0) return null;

    const x = this.vectorTfIdf(conteos);

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

  /** Clase más probable con su confianza y las tres clases con mayor prob. */
  predecir(texto: string): PrediccionGrupo | null {
    const probs = this.probabilidades(texto);
    if (probs === null) return null;

    const orden = probs
      .map((prob, k) => ({ k, prob }))
      .sort((a, b) => b.prob - a.prob);

    return {
      grupo_id: this.modelo.clases[orden[0].k],
      confianza: orden[0].prob,
      top3: orden.slice(0, 3).map(({ k, prob }) => ({
        grupo_id: this.modelo.clases[k],
        prob,
      })),
    };
  }

  /** Nombre de la clase según el mapa embebido en el modelo. */
  nombreGrupo(grupoId: number): string {
    return this.modelo.nombres[String(grupoId)] ?? `Grupo ${grupoId}`;
  }
}
