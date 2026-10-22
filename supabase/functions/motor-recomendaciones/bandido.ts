// ============================================================================
// SmartMoney · Motor de recomendaciones · Bandido Thompson Sampling
// ----------------------------------------------------------------------------
// Funciones PURAS: no leen ni escriben en Supabase. El motor les pasa los
// conteos (de usuario y globales) y recibe los pesos por tipo. El generador
// aleatorio es inyectable para que las pruebas sean deterministas.
//
// Jerarquía del prior:
//   μ_poblacion  = (utiles_tipo + C_DISENO × μ_diseno) / (respuestas + C_DISENO)
//   α            = M_PRIOR × μ_poblacion + utiles_usuario
//   β            = M_PRIOR × (1 − μ_poblacion) + no_utiles_usuario
// El peso del grupo 'bandido' es una muestra Beta(α, β); el de 'control' es el
// de diseño. riesgo_fin_de_mes queda FUERA del bandido.
// ============================================================================

import {
  AB_ACTIVO,
  C_DISENO,
  M_PRIOR,
  MU_DISENO,
  PESO_TIPO_CONTROL,
  TIPOS_BANDIDO,
  type TipoBandido,
} from "./config.ts";

/** Generador aleatorio en [0, 1). */
export type Rng = () => number;

/** Grupo del A/B al que pertenece un usuario. */
export type GrupoExperimento = "bandido" | "control";

/** Respuestas de un tipo: cuántas fueron 'útil' y cuántas 'no útil'. */
export interface ConteoTipo {
  utiles: number;
  no_utiles: number;
}

/** Conteos por tipo (las claves ausentes cuentan como 0). */
export type Conteos = Record<string, ConteoTipo>;

/** Pesos y parámetros Beta calculados para un usuario. */
export interface PesosUsuario {
  grupo: GrupoExperimento;
  /** Peso usado en el puntaje, por tipo del bandido. */
  pesos: Record<TipoBandido, number>;
  /** α por tipo (para trazabilidad). */
  alfa: Record<TipoBandido, number>;
  /** β por tipo (para trazabilidad). */
  beta: Record<TipoBandido, number>;
}

// --- Generadores -------------------------------------------------------------

/**
 * PRNG mulberry32: determinista y reproducible para las pruebas.
 * Devuelve un generador que entrega números en [0, 1).
 */
export function mulberry32(semilla: number): Rng {
  let estado = semilla >>> 0;
  return () => {
    estado = (estado + 0x6D2B79F5) >>> 0;
    let t = estado;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Un número normal estándar (Box–Muller). */
function normalEstandar(rng: Rng): number {
  const u1 = rng() || 1e-12;
  const u2 = rng();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

// --- Distribuciones ----------------------------------------------------------

/**
 * Muestra de una Gamma(forma, 1) por el método de Marsaglia–Tsang, con el
 * ajuste Gamma(a) = Gamma(a + 1) × U^(1/a) para forma < 1.
 */
export function muestraGamma(forma: number, rng: Rng = Math.random): number {
  if (!(forma > 0)) return 0;

  if (forma < 1) {
    const u = rng() || 1e-12;
    return muestraGamma(forma + 1, rng) * Math.pow(u, 1 / forma);
  }

  const d = forma - 1 / 3;
  const c = 1 / Math.sqrt(9 * d);
  for (;;) {
    let x: number;
    let v: number;
    do {
      x = normalEstandar(rng);
      v = 1 + c * x;
    } while (v <= 0);
    v = v * v * v;
    const u = rng();
    if (u < 1 - 0.0331 * x * x * x * x) return d * v;
    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v;
  }
}

/** Muestra de una Beta(a, b) = X / (X + Y) con X~Gamma(a), Y~Gamma(b). */
export function muestraBeta(
  a: number,
  b: number,
  rng: Rng = Math.random,
): number {
  const x = muestraGamma(a, rng);
  const y = muestraGamma(b, rng);
  const total = x + y;
  if (!(total > 0) || !Number.isFinite(total)) return a / (a + b);
  return x / total;
}

// --- Conteos y prior ---------------------------------------------------------

function conteoDe(conteos: Conteos, tipo: string): ConteoTipo {
  const conteo = conteos[tipo];
  return conteo ?? { utiles: 0, no_utiles: 0 };
}

function muDeDiseno(tipo: TipoBandido): number {
  return MU_DISENO[tipo];
}

/**
 * Conteos poblacionales SIN las respuestas del propio usuario (leave-one-out):
 * evita contar dos veces sus clics al construir el prior. Nunca es negativo.
 */
export function conteosPoblacionSinUsuario(
  conteosGlobales: Conteos,
  conteosUsuario: Conteos,
): Conteos {
  const poblacion: Conteos = {};
  for (const tipo of Object.keys(conteosGlobales)) {
    const global = conteoDe(conteosGlobales, tipo);
    const usuario = conteoDe(conteosUsuario, tipo);
    poblacion[tipo] = {
      utiles: Math.max(0, global.utiles - usuario.utiles),
      no_utiles: Math.max(0, global.no_utiles - usuario.no_utiles),
    };
  }
  return poblacion;
}

/**
 * Media poblacional del tipo: mezcla la tasa observada (todos los usuarios) con
 * el prior de diseño. Sin datos devuelve exactamente μ_diseño.
 */
export function mediaPoblacion(tipo: TipoBandido, conteosGlobales: Conteos): number {
  const { utiles, no_utiles } = conteoDe(conteosGlobales, tipo);
  return (utiles + C_DISENO * muDeDiseno(tipo)) /
    (utiles + no_utiles + C_DISENO);
}

/**
 * Parámetros Beta del usuario para el tipo, arrancando del prior poblacional:
 * sin clics α + β = M_PRIOR; con clics, la media se acerca a la tasa observada.
 */
export function parametrosUsuario(
  tipo: TipoBandido,
  conteosUsuario: Conteos,
  muPoblacion: number,
): { alfa: number; beta: number } {
  const { utiles, no_utiles } = conteoDe(conteosUsuario, tipo);
  return {
    alfa: M_PRIOR * muPoblacion + utiles,
    beta: M_PRIOR * (1 - muPoblacion) + no_utiles,
  };
}

// --- A/B y pesos -------------------------------------------------------------

/**
 * Asignación determinística 50/50 por usuario (hash FNV-1a de su uuid): el
 * mismo usuario siempre cae en el mismo grupo. Con AB_ACTIVO = false, todos
 * van al grupo 'bandido'.
 */
export function grupoExperimento(usuarioId: string): GrupoExperimento {
  if (!AB_ACTIVO) return "bandido";

  let hash = 2166136261;
  for (let i = 0; i < usuarioId.length; i++) {
    hash ^= usuarioId.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return ((hash >>> 0) >>> 16) % 2 === 0 ? "bandido" : "control";
}

/**
 * Pesos del usuario: en 'control' son los de diseño; en 'bandido' una muestra
 * Beta(α, β) por tipo. Siempre devuelve α y β por tipo para la trazabilidad.
 */
export function pesosParaUsuario(
  grupo: GrupoExperimento,
  conteosUsuario: Conteos,
  conteosGlobales: Conteos,
  rng: Rng = Math.random,
): PesosUsuario {
  const pesos = {} as Record<TipoBandido, number>;
  const alfa = {} as Record<TipoBandido, number>;
  const beta = {} as Record<TipoBandido, number>;

  // Leave-one-out: el prior no debe contar dos veces los clics del usuario.
  const poblacion = conteosPoblacionSinUsuario(conteosGlobales, conteosUsuario);

  for (const tipo of TIPOS_BANDIDO) {
    const mu = mediaPoblacion(tipo, poblacion);
    const parametros = parametrosUsuario(tipo, conteosUsuario, mu);
    alfa[tipo] = parametros.alfa;
    beta[tipo] = parametros.beta;
    pesos[tipo] = grupo === "control"
      ? PESO_TIPO_CONTROL[tipo]
      : muestraBeta(parametros.alfa, parametros.beta, rng);
  }

  return { grupo, pesos, alfa, beta };
}
