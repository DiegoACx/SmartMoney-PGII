// ============================================================================
// SmartMoney · Clasificador de movimientos · Modelo (funciones puras)
// ----------------------------------------------------------------------------
// Carga el artefacto entrenado (modelo_clasificador.json, 13 grupos de gasto) y
// lo conecta con el predictor genérico de `_shared/clasificador_ngramas.ts`.
//
// Este módulo no toca Supabase ni la red: se puede probar con `deno test`.
// ============================================================================

import modeloJson from "./modelo_clasificador.json" with { type: "json" };

import {
  ClasificadorNgramas,
  type ModeloClasificador,
  type PrediccionGrupo,
} from "../_shared/clasificador_ngramas.ts";

export type {
  CasoPrueba,
  ModeloClasificador,
  PrediccionGrupo,
} from "../_shared/clasificador_ngramas.ts";
export { ngramasCharWb, normalizar } from "../_shared/clasificador_ngramas.ts";

/** Artefacto entrenado (única fuente de verdad del clasificador). */
export const modelo = modeloJson as unknown as ModeloClasificador;

const clasificador = new ClasificadorNgramas(modelo);

/** Probabilidades por clase (en el orden de modelo.clases). */
export function probabilidades(texto: string): number[] | null {
  return clasificador.probabilidades(texto);
}

/** Grupo más probable con su confianza y los tres grupos con mayor prob. */
export function predecir(texto: string): PrediccionGrupo | null {
  return clasificador.predecir(texto);
}

/** Nombre del grupo según el mapa embebido en el modelo. */
export function nombreGrupo(grupoId: number): string {
  return clasificador.nombreGrupo(grupoId);
}
