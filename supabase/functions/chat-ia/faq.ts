// ============================================================================
// SmartMoney · Chat IA · Preguntas frecuentes (ayuda_app)
// ----------------------------------------------------------------------------
// Empareja el mensaje con la pregunta frecuente más parecida usando similitud
// de Jaccard sobre trigramas de caracteres (sin LLM, sin red). El mensaje y
// cada candidato pasan por la MISMA normalización (`normalizar` de _shared), y
// cada entrada se compara con su pregunta, sus ejemplos y sus variantes: se
// conserva la similitud máxima. Si nada se parece lo suficiente, responde con
// la lista de lo que puede hacer el asistente.
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
  variantes: string[];
  respuesta: string;
  accion?: Accion;
}

const PREGUNTAS = faqJson.preguntas as EntradaFaq[];
const LISTA_CAPACIDADES = faqJson.lista_capacidades as string;

/**
 * Trigramas de caracteres de un texto YA normalizado (con `normalizar`) y
 * acolchado.
 */
function trigramas(normalizado: string): Set<string> {
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

/**
 * Candidatos de todas las FAQ (pregunta, ejemplos y variantes) ya normalizados
 * UNA sola vez con `normalizar`: minúsculas, sin tildes (ñ → n), sin signos de
 * puntuación (¿?¡!.,) y sin espacios repetidos. Así «¿Cómo cambio mi
 * contraseña?» y «como cambio mi contrasena» se comparan como el mismo texto,
 * igual que hace el mensaje del usuario.
 */
const CANDIDATOS: { entrada: EntradaFaq; trigramas: Set<string> }[] = PREGUNTAS
  .flatMap((entrada) =>
    [entrada.pregunta, ...entrada.ejemplos, ...entrada.variantes].map((texto) => ({
      entrada,
      trigramas: trigramas(normalizar(texto)),
    }))
  );

/** La pregunta frecuente más parecida al mensaje, o null si ninguna supera el umbral. */
function buscarPregunta(mensaje: string): EntradaFaq | null {
  const delMensaje = trigramas(normalizar(mensaje));
  let mejor: EntradaFaq | null = null;
  let mejorSimilitud = 0;

  for (const candidato of CANDIDATOS) {
    const similitud = jaccard(delMensaje, candidato.trigramas);
    if (similitud > mejorSimilitud) {
      mejorSimilitud = similitud;
      mejor = candidato.entrada;
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
