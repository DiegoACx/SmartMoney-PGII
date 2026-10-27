// ============================================================================
// SmartMoney · Chat IA · conversacion
// ----------------------------------------------------------------------------
// Saludos, agradecimientos, despedidas y la pregunta por el propio bot se
// resuelven con reglas (sin LLM, origen 'plantilla'). El seguimiento
// ("no entendí", "explícamelo más fácil"…) sí usa Gemini para reexplicar el
// último mensaje del asistente, sin cifras nuevas; si falla, cae a plantilla.
//
// Cualquier otra cosa es "fuera de tema": el asistente solo habla de finanzas
// y de la app.
// ============================================================================

import { normalizar } from "../_shared/clasificador_ngramas.ts";
import { buscarGlosario } from "./conocimiento.ts";
import {
  cifrasEnTexto,
  generarConGemini,
  validarTextoLLM,
} from "../_shared/gemini.ts";
import type { RespuestaIntencion } from "./tipos.ts";

/** Tope de caracteres (sin símbolos de Markdown) para la reexplicación. */
export const LLM_MAX_CARACTERES_CONVERSACION = 420;

const INSTRUCCION_SEGUIMIENTO =
  "Eres el asistente financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Reexplica la idea anterior en español colombiano, tuteando, con palabras muy sencillas y sin tecnicismos. Usa esta estructura: una frase inicial que responda directo, si hace falta de 2 a 4 viñetas que empiecen con \"- \" y una frase final corta; el texto, sin contar los símbolos de formato, debe quedar por debajo de 420 caracteres. Puedes poner en **negrita** las cifras clave, pero usa SOLO las cifras que aparezcan en la explicación anterior, escritas exactamente igual; no agregues números nuevos. No uses títulos, enlaces, imágenes, tablas, código ni HTML. Responde solo con el texto, sin comillas ni emojis.";

const EJEMPLOS =
  "Puedes preguntarme «¿cuánto llevo gastado esta semana?», «¿cómo van mis metas?» o «¿cómo registro un movimiento?».";

const RE_SEGUIMIENTO =
  /no entendi|no entiendo|no te entendi|no comprendi|no me quedo claro|no me queda claro|explicalo|explicame|explicamelo|mas facil|mas simple|en palabras simples|otra vez|otra ves|repiteme|repitelo|como si tuviera (5|cinco) anos|no capte|no cacho/;
/**
 * Referencias a la respuesta anterior ("para qué miro eso", "y eso", "cómo
 * así", "explícame mejor") o un "¿por qué?" / "¿para qué?" suelto. Se aplica
 * sobre el texto normalizado (minúsculas, sin tildes ni signos).
 */
const RE_ANAFORA =
  /\b(?:eso|esto|aquello|lo anterior|lo que dijiste|lo que me dijiste|como asi|a que te refieres|explicame mejor|no entendi|no entiendo)\b|^(?:y |pero )?(?:por|para) que(?: seria| es| sirve)?$/;

/** Máximo de palabras para considerar que un mensaje es un seguimiento corto. */
export const MAX_PALABRAS_SEGUIMIENTO = 6;

/**
 * true si el mensaje es una pregunta corta que se refiere a la respuesta
 * anterior: 6 palabras o menos, con una referencia anafórica y sin nombrar un
 * concepto del glosario (si nombra uno, es una pregunta nueva sobre ese tema).
 * Es pura: el manejador decide además si hay una respuesta reciente.
 */
export function esSeguimientoCorto(mensaje: string): boolean {
  const texto = normalizar(mensaje);
  if (texto.length === 0) return false;
  const palabras = texto.split(" ").filter((palabra) => palabra.length > 0);
  if (palabras.length > MAX_PALABRAS_SEGUIMIENTO) return false;
  if (!RE_ANAFORA.test(texto)) return false;
  return buscarGlosario(mensaje) === null;
}

const RE_BOT = /eres un bot|eres un robot|quien eres|que eres|eres humano|eres una ia|eres inteligencia artificial|eres real|con quien hablo/;
const RE_SALUDO =
  /\bhola\b|\bholi\b|\bholaa\b|\bbuenas\b|\bbuenos dias\b|\bbuenas tardes\b|\bbuenas noches\b|\bhey\b|\bque tal\b|\bque mas\b|\bsaludos\b/;
const RE_GRACIAS = /\bgracias\b|te agradezco|muy amable|mil gracias/;
const RE_DESPEDIDA =
  /\badios\b|\bchao\b|\bchau\b|hasta luego|hasta pronto|nos vemos|\bbye\b|\bme voy\b|hasta manana/;

export interface EntradaConversacion {
  mensaje: string;
  ultimoMensajeAsistente: string | null;
  fetchFn: typeof fetch;
  claveLLM?: string | null;
}

/** Respuesta de la intención conversacion. */
export async function responderConversacion(
  entrada: EntradaConversacion,
): Promise<RespuestaIntencion> {
  const texto = normalizar(entrada.mensaje);

  if (RE_SEGUIMIENTO.test(texto)) {
    return await responderSeguimiento(entrada);
  }

  // Pregunta corta sobre la respuesta anterior ("¿para qué miro eso?").
  if (
    esSeguimientoCorto(entrada.mensaje) &&
    entrada.ultimoMensajeAsistente !== null &&
    entrada.ultimoMensajeAsistente.length > 0
  ) {
    return await responderSeguimiento(entrada);
  }

  if (RE_BOT.test(texto)) {
    return {
      respuesta:
        "Soy el asistente de SmartMoney y funciono con inteligencia artificial. Uso tus movimientos, tus metas y las guías de la app para ayudarte con tus finanzas; no soy una persona.",
      origen: "plantilla",
      motivo: "bot",
    };
  }

  if (RE_SALUDO.test(texto)) {
    return {
      respuesta: `¡Hola! Soy tu asistente de SmartMoney. ${EJEMPLOS}`,
      origen: "plantilla",
      motivo: "saludo",
    };
  }

  if (RE_GRACIAS.test(texto)) {
    return {
      respuesta: "¡Con mucho gusto! Aquí estoy para lo que necesites con tus finanzas.",
      origen: "plantilla",
      motivo: "gracias",
    };
  }

  if (RE_DESPEDIDA.test(texto)) {
    return {
      respuesta:
        "¡Hasta pronto! Cuando quieras volvemos a revisar tus finanzas y tus metas.",
      origen: "plantilla",
      motivo: "despedida",
    };
  }

  return {
    respuesta:
      `Solo puedo ayudarte con tus finanzas y con la app. ${EJEMPLOS}`,
    origen: "plantilla",
    motivo: "fuera_de_tema",
  };
}

/** Reexplica el último mensaje del asistente; si no se puede, usa plantilla. */
async function responderSeguimiento(
  entrada: EntradaConversacion,
): Promise<RespuestaIntencion> {
  const anterior = entrada.ultimoMensajeAsistente;
  if (anterior === null || anterior.length === 0) {
    return {
      respuesta:
        `No tengo una respuesta anterior para repetirte, pero puedo ayudarte con tus finanzas. ${EJEMPLOS}`,
      origen: "plantilla",
      motivo: "seguimiento_sin_anterior",
    };
  }

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_SEGUIMIENTO,
      mensaje:
        `Explicación anterior: ${anterior}\nPregunta del usuario sobre esa explicación: "${entrada.mensaje}"\nResponde esa pregunta reexplicando la idea más fácil.`,
    },
    (texto) =>
      validarTextoLLM(
        texto,
        cifrasEnTexto(anterior),
        LLM_MAX_CARACTERES_CONVERSACION,
      ),
    entrada.fetchFn,
    { clave: entrada.claveLLM },
  );

  if (resultado.texto !== null) {
    return {
      respuesta: resultado.texto.trim(),
      origen: "llm",
      motivo: resultado.motivo,
    };
  }

  return {
    respuesta: `Te lo repito con otras palabras: ${anterior}`,
    origen: "plantilla",
    motivo: resultado.motivo,
  };
}
