// ============================================================================
// SmartMoney · Chat IA · Preguntas frecuentes (ayuda_app)
// ----------------------------------------------------------------------------
// Empareja el mensaje con la pregunta frecuente más parecida usando similitud
// de Jaccard sobre trigramas de caracteres (sin LLM, sin red). Si nada se
// parece lo suficiente, responde con la lista de lo que puede hacer el
// asistente.
//
// Este módulo no toca Supabase ni la red: se prueba con `deno test`.
// ============================================================================

import { normalizar } from "../_shared/clasificador_ngramas.ts";
import type { Accion, RespuestaIntencion } from "./tipos.ts";

import faqJson from "./faq.json" with { type: "json" };

/** Similitud mínima (Jaccard de trigramas) para aceptar una pregunta frecuente. */
export const UMBRAL_FAQ = 0.35;

interface EntradaFaq {
  id: string;
  pregunta: string;
  ejemplos: string[];
  respuesta: string;
  accion?: Accion;
}

const PREGUNTAS = faqJson.preguntas as EntradaFaq[];
const LISTA_CAPACIDADES = faqJson.lista_capacidades as string;

/** Trigramas de caracteres de un texto ya normalizado y acolchado. */
function trigramas(texto: string): Set<string> {
  const normalizado = normalizar(texto);
  const acolchado = ` ${normalizado} `;
  const conjunto = new Set<string>();
  if (acolchado.length < 3) {
    if (normalizado.length > 0) conjunto.add(normalizado);
    return conjunto;
  }
  for (let i = 0; i + 3 <= acolchado.length; i++) {
    conjunto.add(acolchado.slice(i, i + 3));
  }
  return conjunto;
}

/** Índice de Jaccard entre dos conjuntos de trigramas (0..1). */
function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let interseccion = 0;
  for (const trigrama of a) {
    if (b.has(trigrama)) interseccion++;
  }
  return interseccion / (a.size + b.size - interseccion);
}

/** La pregunta frecuente más parecida al mensaje, o null si ninguna supera el umbral. */
function buscarPregunta(mensaje: string): EntradaFaq | null {
  const entrada = trigramas(mensaje);
  let mejor: EntradaFaq | null = null;
  let mejorSimilitud = 0;

  for (const item of PREGUNTAS) {
    for (const candidato of [item.pregunta, ...item.ejemplos]) {
      const similitud = jaccard(entrada, trigramas(candidato));
      if (similitud > mejorSimilitud) {
        mejorSimilitud = similitud;
        mejor = item;
      }
    }
  }

  return mejorSimilitud >= UMBRAL_FAQ ? mejor : null;
}

/** Respuesta de la intención ayuda_app para un mensaje. */
export function responderFaq(mensaje: string): RespuestaIntencion {
  const encontrada = buscarPregunta(mensaje);
  if (encontrada === null) {
    return {
      respuesta: LISTA_CAPACIDADES,
      origen: "faq",
      motivo: "faq_sin_match",
    };
  }

  const respuesta: RespuestaIntencion = {
    respuesta: encontrada.respuesta,
    origen: "faq",
    motivo: `faq:${encontrada.id}`,
  };
  if (encontrada.accion !== undefined) respuesta.accion = encontrada.accion;
  return respuesta;
}
