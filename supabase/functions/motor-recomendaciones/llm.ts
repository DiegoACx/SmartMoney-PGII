// ============================================================================
// SmartMoney · Motor de recomendaciones · Redacción con Gemini (LLM)
// ----------------------------------------------------------------------------
// Redacta el texto de UNA recomendación con Gemini y valida la salida antes de
// que el motor la guarde. Ante cualquier problema (sin clave, timeout, límite
// 429, error HTTP o texto no válido) devuelve null y el motor usa la plantilla.
//
// La mecánica de la llamada (timeout, respaldo de modelo, thinkingConfig,
// validación de la salida y clasificación de motivos) vive en
// `_shared/gemini.ts`. Aquí queda lo ESPECÍFICO de los hallazgos: qué cifras
// puede usar el modelo y cómo se arma el prompt de la recomendación.
//
// Privacidad (Ley 1581 de 2020): a Gemini solo se le envían el tipo, el nombre
// del grupo / categoría / meta o el título de la lección, y las cifras ya
// formateadas. NUNCA ids, usuario_id, correos, nombres de usuario ni
// descripciones de movimientos.
// ============================================================================

import {
  formatearCOP,
  generarConGemini,
  validarTextoLLM,
  type OpcionesLLM,
  type ResultadoLLM,
} from "../_shared/gemini.ts";
import type { HallazgoPuntuado } from "./puntaje.ts";

export type { MotivoLLM, OpcionesLLM, ResultadoLLM } from "../_shared/gemini.ts";
export { validarTextoLLM };

const INSTRUCCION_SISTEMA =
  "Eres el asistente financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Redacta UNA recomendación de máximo 2 frases y 280 caracteres, en español colombiano, tuteando, con tono cercano y respetuoso, sin regaños. Usa SOLO las cifras que te doy, escritas exactamente igual; no inventes números, porcentajes ni fechas. Incluye una acción concreta. No recomiendes bancos, productos financieros, créditos ni inversiones específicas. Responde solo con el texto, sin comillas ni emojis.";

// --- Cifras permitidas -------------------------------------------------------

function valorNumerico(
  datos: Record<string, unknown>,
  clave: string,
): number {
  const valor = datos[clave];
  return typeof valor === "number" && Number.isFinite(valor) ? valor : 0;
}

/** '2026-10-12' → ['12', '2026']: los números que se escriben al decir la fecha. */
function valoresDeFecha(fecha: string): string[] {
  if (!/^\d{4}-\d{2}-\d{2}/.test(fecha)) return [];
  return [String(Number(fecha.slice(8, 10))), String(Number(fecha.slice(0, 4)))];
}

/**
 * Cifras que el LLM puede usar en su texto, ya formateadas igual que en las
 * plantillas. Cualquier otro número que aparezca invalida la respuesta.
 */
export function cifrasPermitidas(hallazgo: HallazgoPuntuado): string[] {
  const datos = hallazgo.datos;
  switch (hallazgo.tipo) {
    case "sobregasto_categoria":
      return [
        formatearCOP(valorNumerico(datos, "gastado_mes")),
        formatearCOP(valorNumerico(datos, "proyeccion")),
        formatearCOP(valorNumerico(datos, "normal_mensual")),
        String(valorNumerico(datos, "dias_restantes")),
      ];
    case "gasto_anomalo":
      return [
        formatearCOP(valorNumerico(datos, "monto")),
        formatearCOP(valorNumerico(datos, "mediana_monto")),
        ...valoresDeFecha(String(datos["fecha"] ?? "")),
      ];
    case "aporte_meta":
      return [
        formatearCOP(valorNumerico(datos, "aporte_sugerido")),
        formatearCOP(valorNumerico(datos, "ritmo_30_dias")),
        ...valoresDeFecha(String(datos["fecha_limite"] ?? "")),
      ];
    case "leccion_sugerida":
      return [];
    case "logro": {
      const normal = valorNumerico(datos, "normal_personal_mensual");
      const gasto = valorNumerico(datos, "gasto_mes");
      const porcentaje = normal > 0
        ? Math.round((1 - gasto / normal) * 100)
        : 0;
      return [formatearCOP(gasto), formatearCOP(normal), `${porcentaje} %`];
    }
    case "riesgo_fin_de_mes":
      return [
        formatearCOP(valorNumerico(datos, "faltante")),
        String(valorNumerico(datos, "dias_restantes")),
      ];
  }
}

// --- Prompt ------------------------------------------------------------------

/** Contexto mínimo y sin datos personales que se le envía al modelo. */
function construirMensaje(
  hallazgo: HallazgoPuntuado,
  textoPlantilla: string,
): string {
  const datos = hallazgo.datos;
  const lineas: string[] = [`Tipo de recomendación: ${hallazgo.tipo}`];

  const nombres: Array<[string, unknown]> = [
    ["Grupo de gasto", datos["nombre_grupo"]],
    ["Categoría", datos["nombre_categoria"]],
    ["Meta", datos["nombre_meta"]],
    ["Lección", datos["titulo"]],
  ];
  for (const [etiqueta, valor] of nombres) {
    if (typeof valor === "string" && valor.length > 0) {
      lineas.push(`${etiqueta}: ${valor}`);
    }
  }

  const cifras = cifrasPermitidas(hallazgo);
  lineas.push(
    cifras.length > 0
      ? `Cifras que puedes usar (escríbelas exactamente así): ${cifras.join(", ")}.`
      : "No menciones ninguna cifra.",
  );
  lineas.push(
    `Referencia del contenido mínimo que debes conservar: ${textoPlantilla}`,
  );

  return lineas.join("\n");
}

// --- Llamada a Gemini --------------------------------------------------------

/**
 * Pide a Gemini el texto de la recomendación y lo valida. Nunca lanza.
 *
 * El respaldo de modelo y la validación de cifras los aplica `generarConGemini`
 * con `cifrasPermitidas(hallazgo)`. Si nada sirve, el motor cae a la plantilla.
 */
export async function redactarConGemini(
  hallazgo: HallazgoPuntuado,
  textoPlantilla: string,
  fetchFn: typeof fetch = fetch,
  opciones: OpcionesLLM = {},
): Promise<ResultadoLLM> {
  return await generarConGemini(
    {
      instruccion: INSTRUCCION_SISTEMA,
      mensaje: construirMensaje(hallazgo, textoPlantilla),
    },
    (texto) => validarTextoLLM(texto, cifrasPermitidas(hallazgo)),
    fetchFn,
    opciones,
  );
}
