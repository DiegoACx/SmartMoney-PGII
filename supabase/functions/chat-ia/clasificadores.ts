// ============================================================================
// SmartMoney · Chat IA · Clasificadores
// ----------------------------------------------------------------------------
// Conecta los dos artefactos entrenados con el predictor genérico de
// `_shared/clasificador_ngramas.ts`:
//   · modelo_intencion.json   → 6 intenciones del chat;
//   · modelo_clasificador.json → 13 grupos de gasto (para saber de qué grupo
//     pregunta el usuario en la intención consultar_datos).
//
// Este módulo no toca Supabase ni la red: se prueba con `deno test`.
// ============================================================================

import {
  ClasificadorNgramas,
  type ModeloClasificador,
  type PrediccionGrupo,
} from "../_shared/clasificador_ngramas.ts";
import type { Intencion } from "./tipos.ts";

import modeloIntencionJson from "./modelo_intencion.json" with { type: "json" };
import modeloGruposJson from "./modelo_clasificador.json" with { type: "json" };

/** Confianza mínima para aceptar la intención predicha. */
export const UMBRAL_INTENCION = 0.45;

const clasificadorIntencion = new ClasificadorNgramas(
  modeloIntencionJson as unknown as ModeloClasificador,
);
const clasificadorGrupos = new ClasificadorNgramas(
  modeloGruposJson as unknown as ModeloClasificador,
);

export interface ClasificacionIntencion {
  /** null cuando el texto no aporta ningún n-grama conocido. */
  intencion: Intencion | null;
  confianza: number;
}

/** Intención más probable del mensaje y su confianza (0 cuando no hay señal). */
export function clasificarIntencion(texto: string): ClasificacionIntencion {
  const prediccion = clasificadorIntencion.predecir(texto);
  if (prediccion === null) return { intencion: null, confianza: 0 };
  return {
    intencion: clasificadorIntencion.nombreGrupo(prediccion.grupo_id) as Intencion,
    confianza: prediccion.confianza,
  };
}

/** Lo mínimo que necesita consultar_datos de un clasificador de grupos. */
export interface ClasificadorGrupos {
  predecir(texto: string): PrediccionGrupo | null;
  nombreGrupo(grupoId: number): string;
}

/** Clasificador de grupos de gasto real (13 grupos). */
export const grupos: ClasificadorGrupos = {
  predecir: (texto) => clasificadorGrupos.predecir(texto),
  nombreGrupo: (grupoId) => clasificadorGrupos.nombreGrupo(grupoId),
};
