// ============================================================================
// SmartMoney · Chat IA · aprender_concepto
// ----------------------------------------------------------------------------
// Dos caminos:
//   · CON fuente: el mensaje coincide con una entrada del glosario o con una
//     lección. Gemini explica SOLO con ese texto (definición + ejemplo y/o el
//     inicio de la lección) y las únicas cifras permitidas son las del texto.
//   · SIN fuente: Gemini responde con conocimiento general bajo reglas
//     estrictas (máximo 3 frases, SIN cifras, sin bancos ni productos por
//     nombre) y cierra con el aviso de confirmar en una fuente oficial.
//
// Si Gemini falla, siempre hay una plantilla: la definición y el ejemplo del
// glosario (o el inicio de la lección) y, en el caso general, la invitación a
// mirar tres conceptos del glosario.
// ============================================================================

import {
  cifrasEnTexto,
  generarConGemini,
  validarTextoLLM,
} from "../_shared/gemini.ts";
import {
  buscarConocimiento,
  LARGO_FUENTE_LECCION,
  sugerirConceptos,
  type Coincidencia,
} from "./conocimiento.ts";
import type { RepositorioChat } from "./repositorio.ts";
import type { RespuestaIntencion } from "./tipos.ts";

/** Tope de caracteres del texto redactado por Gemini en esta intención. */
export const LLM_MAX_CARACTERES_APRENDIZAJE = 450;

/** Cierre obligatorio de una explicación sin fuente en el glosario. */
export const CIERRE_FUENTE_OFICIAL =
  "Te recomiendo confirmarlo con una fuente oficial.";

/** Texto de arranque cuando Gemini no puede responder sin fuente. */
export const SIN_INFORMACION =
  "Todavía no tengo información confiable sobre eso.";

const INSTRUCCION_FUENTE =
  "Eres el asistente financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Explica el concepto en máximo 4 frases cortas, en español colombiano sencillo, tuteando. Usa SOLO el texto fuente que te doy: no agregues datos, cifras ni condiciones que no estén ahí. Si el texto fuente no explica el concepto preguntado, responde exactamente " +
  SIN_INFORMACION +
  " Las únicas cifras que puedes escribir son las del texto fuente, igual. No menciones bancos ni productos por su nombre. No menciones \"el texto\", \"la fuente\" ni \"lo que me das\": respóndele al usuario directamente, sin hablar de dónde sacaste la información. Responde solo con el texto, sin comillas ni emojis.";

/** Frases prohibidas: delatan que el modelo habla de la fuente y no del concepto. */
const FRASES_PROHIBIDAS = ["el texto", "la fuente", "lo que me das"];

/** true si el texto menciona la fuente en vez de explicarle al usuario. */
function mencionaFuente(texto: string): boolean {
  const plano = texto.toLowerCase();
  return FRASES_PROHIBIDAS.some((frase) => plano.includes(frase));
}

const INSTRUCCION_GENERAL =
  "Eres el asistente financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Explica la idea en máximo 3 frases, en español colombiano sencillo, tuteando. No escribas cifras: nada de porcentajes, montos, pesos ni números. No menciones bancos ni productos financieros por su nombre. Termina el texto exactamente con esta frase: " +
  CIERRE_FUENTE_OFICIAL +
  " Responde solo con el texto, sin comillas ni emojis.";

export interface DepsAprendizaje {
  repositorio: RepositorioChat;
  fetchFn: typeof fetch;
  claveLLM?: string | null;
}

/** Respuesta de la intención aprender_concepto. */
export async function responderAprendizaje(
  mensaje: string,
  deps: DepsAprendizaje,
): Promise<RespuestaIntencion> {
  const lecciones = await deps.repositorio.leerLeccionesValidas();
  const coincidencia = buscarConocimiento(mensaje, lecciones);

  if (coincidencia.glosario !== null || coincidencia.leccion !== null) {
    return await responderConFuente(mensaje, coincidencia, deps);
  }
  return await responderGeneral(mensaje, deps);
}

// --- Con fuente (glosario y/o lección) ---------------------------------------

/** Motivo: el del mayor puntaje; en empate manda el glosario por ser más preciso. */
function motivoDeFuente(coincidencia: Coincidencia): string {
  const glosario = coincidencia.glosario;
  const leccion = coincidencia.leccion;
  if (glosario === null) return `aprender:leccion:${leccion!.leccion.id}`;
  if (leccion === null) return `aprender:glosario:${glosario.entrada.id}`;
  return glosario.puntaje >= leccion.puntaje
    ? `aprender:glosario:${glosario.entrada.id}`
    : `aprender:leccion:${leccion.leccion.id}`;
}

/** Texto fuente que se le pasa a Gemini: definición + ejemplo y/o la lección. */
function textoFuente(coincidencia: Coincidencia): string {
  const partes: string[] = [];
  if (coincidencia.glosario !== null) {
    const { termino, definicion, ejemplo } = coincidencia.glosario.entrada;
    partes.push(`Definición de ${termino}: ${definicion}`);
    partes.push(`Ejemplo: ${ejemplo}`);
  }
  if (coincidencia.leccion !== null) {
    const { titulo, contenido } = coincidencia.leccion.leccion;
    partes.push(
      `Lección "${titulo}": ${(contenido ?? "").slice(0, LARGO_FUENTE_LECCION)}`,
    );
  }
  return partes.join("\n");
}

/**
 * Plantilla sin LLM: la definición y el ejemplo del glosario y, si no hay
 * entrada, el inicio de la lección.
 */
function plantillaConFuente(coincidencia: Coincidencia): string {
  if (coincidencia.glosario !== null) {
    const { definicion, ejemplo } = coincidencia.glosario.entrada;
    return `${definicion} ${ejemplo}`;
  }
  const { titulo, contenido } = coincidencia.leccion!.leccion;
  return `${titulo}: ${(contenido ?? "").slice(0, LARGO_FUENTE_LECCION)}`;
}

async function responderConFuente(
  mensaje: string,
  coincidencia: Coincidencia,
  deps: DepsAprendizaje,
): Promise<RespuestaIntencion> {
  const motivo = motivoDeFuente(coincidencia);
  const fuente = textoFuente(coincidencia);

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_FUENTE,
      mensaje: `Pregunta del usuario: "${mensaje}"\nTexto fuente:\n${fuente}`,
    },
    (texto) => {
      const base = validarTextoLLM(
        texto,
        cifrasEnTexto(fuente),
        LLM_MAX_CARACTERES_APRENDIZAJE,
      );
      if (!base.valido) return base;
      // Hablar de la fuente (en vez de responderle al usuario) invalida el texto.
      if (mencionaFuente(texto)) {
        return { valido: false, motivo: "menciona_fuente" };
      }
      return { valido: true, motivo: "ok" };
    },
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  // El modelo pudo decir que la fuente no explica el concepto (SIN_INFORMACION)
  // o hablar de la fuente: en ambos casos se responde por la rama general.
  if (
    (resultado.texto === null &&
      resultado.motivo === "validacion:menciona_fuente") ||
    (resultado.texto !== null && resultado.texto.trim() === SIN_INFORMACION)
  ) {
    return await responderGeneral(mensaje, deps);
  }

  const respuesta: RespuestaIntencion = {
    respuesta: resultado.texto !== null
      ? resultado.texto.trim()
      : plantillaConFuente(coincidencia),
    origen: resultado.texto !== null ? "llm" : "plantilla",
    motivo: resultado.texto !== null ? motivo : `${motivo}:${resultado.motivo}`,
  };
  // Si la coincidencia trae lección, se ofrece el atajo para abrirla.
  if (coincidencia.leccion !== null) {
    respuesta.accion = {
      tipo: "abrir_leccion",
      escalon_id: coincidencia.leccion.leccion.id,
    };
  }
  return respuesta;
}

// --- Sin fuente (conocimiento general) ---------------------------------------

/**
 * El texto general no puede traer cifras (cifras permitidas = []) ni saltarse
 * el cierre que invita a confirmar en una fuente oficial.
 */
function validarGeneral(texto: string): { valido: boolean; motivo: string } {
  const general = validarTextoLLM(
    texto,
    [],
    LLM_MAX_CARACTERES_APRENDIZAJE,
  );
  if (!general.valido) return general;
  if (!texto.trim().endsWith(CIERRE_FUENTE_OFICIAL)) {
    return { valido: false, motivo: "sin_fuente_oficial" };
  }
  return { valido: true, motivo: "ok" };
}

async function responderGeneral(
  mensaje: string,
  deps: DepsAprendizaje,
): Promise<RespuestaIntencion> {
  const resultado = await generarConGemini(
    { instruccion: INSTRUCCION_GENERAL, mensaje },
    validarGeneral,
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  if (resultado.texto !== null) {
    return {
      respuesta: resultado.texto.trim(),
      origen: "llm",
      motivo: "aprender:general",
    };
  }

  const sugeridos = sugerirConceptos().map((entrada) => entrada.termino);
  return {
    respuesta:
      `${SIN_INFORMACION} Puedes empezar por estos temas: ${sugeridos.join(", ")}.`,
    origen: "plantilla",
    motivo: `aprender:general:${resultado.motivo}`,
  };
}
