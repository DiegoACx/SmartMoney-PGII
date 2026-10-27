// ============================================================================
// SmartMoney · Clasificador de movimientos · Memoria por usuario
// ----------------------------------------------------------------------------
// Antes de consultar el modelo general, se revisa si el usuario ya registró un
// egreso con la MISMA descripción (comparada sin mayúsculas, tildes ni
// puntuación). Si existe, se sugiere la categoría que el usuario eligió la
// última vez: así su propia corrección se respeta en los siguientes registros.
//
// El modelo entrenado no cambia: la memoria es por usuario y vive en sus
// propias transacciones. Las sugerencias que salen de aquí se marcan con
// VERSION_MEMORIA en `version_modelo`, para separarlas del modelo en el
// análisis del piloto.
// ============================================================================

import { normalizar } from "./modelo.ts";

/** Valor de `version_modelo` para las sugerencias que salen de la memoria. */
export const VERSION_MEMORIA = "memoria-usuario-v1";

/** Máximo de egresos recientes que se revisan. */
export const LIMITE_HISTORIAL_MEMORIA = 300;

/** Egreso previo del usuario, con la categoría que quedó guardada. */
export interface EgresoPrevio {
  descripcion: string | null;
  categoria_id: string | null;
  categoria_nombre: string | null;
  grupo_id: number | null;
}

/** Categoría recordada para una descripción. */
export interface Recuerdo {
  categoria_id: string;
  categoria_nombre: string;
  grupo_id: number;
}

/**
 * Busca la descripción en el historial (ordenado del más reciente al más
 * antiguo) y devuelve la categoría del egreso más reciente que coincida.
 * Devuelve null si no hay coincidencia o si la descripción queda vacía al
 * normalizarla. Se ignoran egresos sin categoría o sin grupo.
 */
export function buscarEnMemoria(
  descripcion: string,
  historial: EgresoPrevio[],
): Recuerdo | null {
  const clave = normalizar(descripcion);
  if (clave.length === 0) return null;

  for (const egreso of historial) {
    if (!egreso.descripcion || !egreso.categoria_id) continue;
    if (egreso.grupo_id === null || !Number.isFinite(egreso.grupo_id)) continue;
    if (normalizar(egreso.descripcion) !== clave) continue;
    return {
      categoria_id: egreso.categoria_id,
      categoria_nombre: egreso.categoria_nombre ?? "",
      grupo_id: egreso.grupo_id,
    };
  }
  return null;
}
