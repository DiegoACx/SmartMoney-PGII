// ============================================================================
// SmartMoney · Motor de recomendaciones · Puntaje y selección
// ----------------------------------------------------------------------------
// Funciones PURAS: reciben hallazgos ya detectados y devuelven los puntajes y
// las recomendaciones elegidas. No leen ni escriben en Supabase.
// ============================================================================

import {
  DIAS_REPETICION,
  FACTOR_REPETICION,
  MAX_RECOMENDACIONES,
  PUNTAJE_MINIMO,
  TIPOS_SELECCIONABLES,
  type TipoHallazgo,
} from "./config.ts";
import type { HallazgoBase } from "./detectores.ts";
import { diasEntre } from "./estadistica.ts";

/** Recomendación ya emitida, en lo que respecta a la repetición. */
export interface RecomendacionPrevia {
  tipo: TipoHallazgo;
  /** Entidad señalada, tal como quedó en hallazgos.datos.objetivo. */
  objetivo: string;
  /** Fecha de creación de la recomendación, 'YYYY-MM-DD' o ISO completo. */
  creadoEn: string;
}

export interface HallazgoPuntuado extends HallazgoBase {
  confianza: number;
  repeticion: number;
  peso_tipo_usado: number;
  puntaje: number;
}

/** confianza = 0,5 + 0,5 × p. */
export function calcularConfianza(p: number): number {
  return 0.5 + 0.5 * p;
}

/** repeticion = 0,2 si el mismo objetivo ya se recomendó hace poco; si no, 1. */
export function calcularRepeticion(esRepetido: boolean): number {
  return esRepetido ? FACTOR_REPETICION : 1;
}

/** puntaje = peso_tipo × severidad × impacto × confianza × repeticion. */
export function calcularPuntaje(params: {
  peso_tipo: number;
  severidad: number;
  impacto: number;
  confianza: number;
  repeticion: number;
}): number {
  return params.peso_tipo * params.severidad * params.impacto *
    params.confianza * params.repeticion;
}

/** ¿El mismo tipo con el mismo objetivo se recomendó en los últimos 7 días? */
export function esRepeticion(
  hallazgo: HallazgoBase,
  previas: RecomendacionPrevia[],
  hoy: string,
): boolean {
  return previas.some((previa) =>
    previa.tipo === hallazgo.tipo &&
    previa.objetivo === hallazgo.objetivo &&
    diasEntre(previa.creadoEn, hoy) <= DIAS_REPETICION
  );
}

/** Puntúa todos los hallazgos, sin descartar ninguno. */
export function puntuarHallazgos(params: {
  hallazgos: HallazgoBase[];
  previas: RecomendacionPrevia[];
  hoy: string;
  obtenerPeso: (tipo: TipoHallazgo) => number;
}): HallazgoPuntuado[] {
  const { hallazgos, previas, hoy, obtenerPeso } = params;
  return hallazgos.map((hallazgo) => {
    const confianza = calcularConfianza(hallazgo.p);
    const repeticion = calcularRepeticion(
      esRepeticion(hallazgo, previas, hoy),
    );
    const peso_tipo_usado = obtenerPeso(hallazgo.tipo);
    return {
      ...hallazgo,
      confianza,
      repeticion,
      peso_tipo_usado,
      puntaje: calcularPuntaje({
        peso_tipo: peso_tipo_usado,
        severidad: hallazgo.severidad,
        impacto: hallazgo.impacto,
        confianza,
        repeticion,
      }),
    };
  });
}

function mejorPorPuntaje(
  hallazgos: HallazgoPuntuado[],
): HallazgoPuntuado | null {
  let mejor: HallazgoPuntuado | null = null;
  for (const hallazgo of hallazgos) {
    if (mejor === null || hallazgo.puntaje > mejor.puntaje) mejor = hallazgo;
  }
  return mejor;
}

/**
 * Selección de recomendaciones:
 *   1. riesgo_fin_de_mes, si existe, va siempre primero.
 *   2. el mejor puntaje entre los otros cinco tipos, si supera PUNTAJE_MINIMO.
 *   3. si ninguno pasa el umbral, el mejor logro o lección sugerida.
 * Nunca emite más de MAX_RECOMENDACIONES (2).
 */
export function seleccionar(
  hallazgos: HallazgoPuntuado[],
  max: number = MAX_RECOMENDACIONES,
): HallazgoPuntuado[] {
  const seleccionados: HallazgoPuntuado[] = [];

  const riesgos = hallazgos.filter((h) => h.tipo === "riesgo_fin_de_mes");
  const riesgo = mejorPorPuntaje(riesgos);
  if (riesgo) seleccionados.push(riesgo);

  const otros = hallazgos.filter((h) =>
    TIPOS_SELECCIONABLES.includes(h.tipo)
  );
  const mejor = mejorPorPuntaje(otros);

  if (mejor && mejor.puntaje >= PUNTAJE_MINIMO) {
    if (seleccionados.length < max) seleccionados.push(mejor);
    return seleccionados;
  }

  const respaldo = mejorPorPuntaje(
    otros.filter((h) => h.tipo === "logro" || h.tipo === "leccion_sugerida"),
  );
  if (respaldo && seleccionados.length < max) seleccionados.push(respaldo);

  return seleccionados.slice(0, max);
}
