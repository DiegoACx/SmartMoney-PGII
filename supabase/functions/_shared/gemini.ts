// ============================================================================
// SmartMoney · Gemini (LLM) · Piezas compartidas
// ----------------------------------------------------------------------------
// Todo lo genérico de una llamada a Gemini desde una Edge Function:
//   · la petición con timeout, respaldo de modelo y thinkingConfig;
//   · la clasificación de motivos (para el log de auditoría);
//   · validarTextoLLM (validación previa de la salida del modelo);
//   · formatearCOP (pesos colombianos, separador de miles con punto);
//   · cifrasEnTexto (números presentes en un texto, para reutilizarlos como
//     cifras permitidas al pedir una reexplicación).
//
// Lo ESPECÍFICO de cada función (qué prompt se arma y qué cifras se permiten)
// se queda en su propio módulo: motor-recomendaciones/llm.ts, chat-ia/*.
//
// Privacidad (Ley 1581 de 2020): a Gemini solo deben llegar textos sin datos
// personales. La clave se lee de Deno.env ("GEMINI_API_KEY") y viaja en el
// header x-goog-api-key: nunca en la URL ni en los logs.
// ============================================================================

/** Modelo de Gemini usado por defecto. */
export const GEMINI_MODELO = "gemini-3.5-flash";

/** Modelo al que se cae una sola vez si el principal da 404 o 503. */
export const GEMINI_MODELO_RESPALDO = "gemini-3.5-flash-lite";

/** Tiempo máximo (ms) que se espera la respuesta de Gemini. */
export const GEMINI_TIMEOUT_MS = 8000;

/** Longitud máxima del texto que puede devolver el LLM. */
export const LLM_MAX_CARACTERES = 280;

/**
 * Motivo por el que el texto terminó saliendo (o no) del LLM:
 *   ok                              → texto de Gemini válido
 *   timeout                         → se agotó el timeout
 *   sin_clave                       → falta GEMINI_API_KEY
 *   error_http:<código>:<estado>    → respuesta HTTP con error (404:NOT_FOUND, 429:RESOURCE_EXHAUSTED…)
 *   error_red                       → no hubo respuesta HTTP (fallo de red o JSON ilegible)
 *   validacion:<motivo>             → llegó texto pero no pasó el validador
 *                                    (validacion:truncado también cuando el
 *                                    modelo no terminó: finishReason ≠ STOP)
 *   gemini_429_principal_respaldo_ok → el principal dio 429 (cuota agotada) y el
 *                                    respaldo sí redactó un texto válido
 *   gemini_429_ambos_plantilla       → el principal dio 429 y el respaldo
 *                                    tampoco sirvió (429 u otro fallo)
 */
export type MotivoLLM =
  | "ok"
  | "timeout"
  | "sin_clave"
  | "error_red"
  | "gemini_429_principal_respaldo_ok"
  | "gemini_429_ambos_plantilla"
  | `error_http:${string}`
  | `validacion:${string}`;

export interface ResultadoLLM {
  /** Texto de Gemini ya validado; null si hay que caer a la plantilla. */
  texto: string | null;
  /** Modelo del último intento realizado (el principal si no hubo respaldo). */
  modelo: string;
  motivo: MotivoLLM;
}

/** Inyecciones para las pruebas: timeout corto y clave sin tocar el entorno. */
export interface OpcionesLLM {
  timeoutMs?: number;
  clave?: string | null;
  /** Sobrescribe el modelo principal (por defecto GEMINI_MODELO). */
  modelo?: string;
  /** Sobrescribe el modelo de respaldo (por defecto GEMINI_MODELO_RESPALDO). */
  modeloRespaldo?: string;
}

/** Lo mínimo que se le envía a Gemini: instrucción de sistema y mensaje. */
export interface SolicitudLLM {
  instruccion: string;
  mensaje: string;
}

/** Valida el texto devuelto por Gemini; `ok` significa que se puede usar. */
export type ValidadorTexto = (
  texto: string,
) => { valido: boolean; motivo: string };

// --- Formato de moneda -------------------------------------------------------

/** '$1.234.567' (redondeado al peso, separador de miles con punto). */
export function formatearCOP(valor: number): string {
  const redondeado = Math.round(Math.abs(valor));
  const conPuntos = String(redondeado).replace(
    /\B(?=(\d{3})+(?!\d))/g,
    ".",
  );
  return `${valor < 0 ? "-" : ""}$${conPuntos}`;
}

// --- Validación de la salida -------------------------------------------------

function recortarComillas(texto: string): string {
  const recortado = texto.trim();
  return recortado.replace(/^["'“”«»]+/, "").replace(/["'“”«»]+$/, "").trim();
}

/**
 * Cómo debe cerrar un texto completo: punto, cierre de interrogación o de
 * exclamación, comilla o paréntesis. Si termina en cualquier otra cosa es que
 * el modelo se cortó a mitad de la frase (o lo cortó MAX_TOKENS).
 */
const RE_CIERRE_TEXTO = /[.!?»"')]\s*$/;

/** Números presentes en un texto, sin $, % ni separador de miles. */
function extraerNumeros(texto: string): number[] {
  const limpio = texto.replace(/[$\s%]/g, " ");
  const coincidencias = limpio.match(/\d[\d.]*\d|\d/g) ?? [];
  return coincidencias.map((token) => Number(token.replace(/\./g, "")));
}

/** Números de un texto ya convertidos a texto, listos para validarTextoLLM. */
export function cifrasEnTexto(texto: string): string[] {
  return extraerNumeros(texto).map((valor) => String(valor));
}

function numeroDeCifra(cifra: string): number {
  return extraerNumeros(cifra)[0] ?? Number.NaN;
}

/**
 * Rechaza el texto del LLM si está vacío, pasa del límite de caracteres, trae
 * una URL, quedó cortado a mitad de frase (no cierra con . ! ? » " ) o menciona
 * algún número que no esté entre las cifras permitidas.
 *
 * `maxCaracteres` permite que una intención con más contexto (por ejemplo
 * simular_escenario) use un tope mayor sin cambiar el comportamiento por
 * defecto del resto.
 */
export function validarTextoLLM(
  texto: string,
  cifrasPermitidas: string[],
  maxCaracteres: number = LLM_MAX_CARACTERES,
): { valido: boolean; motivo: string } {
  // El cierre se mira sobre el texto tal cual: recortarComillas le quitaría la
  // comilla final, que sí es un cierre válido.
  const bruto = (texto ?? "").trim();
  const limpio = recortarComillas(texto ?? "");
  if (limpio.length === 0) return { valido: false, motivo: "vacio" };
  if (limpio.length > maxCaracteres) {
    return { valido: false, motivo: "largo" };
  }
  if (/https?:\/\/|www\./i.test(limpio)) return { valido: false, motivo: "url" };
  if (!RE_CIERRE_TEXTO.test(bruto)) return { valido: false, motivo: "truncado" };

  const permitidos = new Set(
    cifrasPermitidas.map(numeroDeCifra).filter((valor) => Number.isFinite(valor)),
  );
  for (const valor of extraerNumeros(limpio)) {
    if (!permitidos.has(valor)) {
      return { valido: false, motivo: `cifra_no_permitida:${valor}` };
    }
  }
  return { valido: true, motivo: "ok" };
}

// --- Llamada a Gemini --------------------------------------------------------

function obtenerClave(): string | null {
  try {
    const clave = Deno.env.get("GEMINI_API_KEY");
    return clave && clave.length > 0 ? clave : null;
  } catch {
    return null;
  }
}

function extraerTexto(cuerpo: unknown): string | null {
  const candidatos = (cuerpo as { candidates?: unknown } | null)?.candidates;
  if (!Array.isArray(candidatos) || candidatos.length === 0) return null;
  const partes = (candidatos[0] as { content?: { parts?: unknown } } | null)
    ?.content?.parts;
  if (!Array.isArray(partes) || partes.length === 0) return null;
  const texto = (partes[0] as { text?: unknown } | null)?.text;
  return typeof texto === "string" ? texto : null;
}

/**
 * `finishReason` del primer candidato ("STOP", "MAX_TOKENS", "SAFETY"…), o null
 * si el cuerpo no lo trae. Cualquier valor distinto de "STOP" significa que el
 * modelo no llegó a terminar el texto.
 */
function extraerFinDeRespuesta(cuerpo: unknown): string | null {
  const candidatos = (cuerpo as { candidates?: unknown } | null)?.candidates;
  if (!Array.isArray(candidatos) || candidatos.length === 0) return null;
  const fin = (candidatos[0] as { finishReason?: unknown } | null)?.finishReason;
  return typeof fin === "string" && fin.length > 0 ? fin : null;
}

/** `x-goog-api-key` va en el header: nunca en la URL ni en los logs. */
function cuerpoPeticion(
  solicitud: SolicitudLLM,
  conThinking: boolean,
): Record<string, unknown> {
  // Los modelos Gemini 3.x razonan antes de responder y esos tokens cuentan en
  // maxOutputTokens, así que se pide el nivel más bajo y un tope holgado.
  const generationConfig: Record<string, unknown> = {
    temperature: 0.4,
    maxOutputTokens: 1024,
  };
  if (conThinking) {
    generationConfig["thinkingConfig"] = { thinkingLevel: "low" };
  }
  return {
    systemInstruction: { parts: [{ text: solicitud.instruccion }] },
    contents: [{
      role: "user",
      parts: [{ text: solicitud.mensaje }],
    }],
    generationConfig,
  };
}

/** `error.status` de Google ('NOT_FOUND', 'UNAVAILABLE'…) o null si no viene. */
async function estadoGoogle(respuesta: Response): Promise<string | null> {
  try {
    const cuerpo = await respuesta.json();
    const estado = (cuerpo as { error?: { status?: unknown } } | null)
      ?.error?.status;
    return typeof estado === "string" && estado.length > 0 ? estado : null;
  } catch {
    return null;
  }
}

/** Resultado de un envío: `http` es null cuando no hubo respuesta HTTP. */
interface IntentoLLM {
  texto: string | null;
  http: number | null;
  motivo: MotivoLLM;
}

interface Envio {
  solicitud: SolicitudLLM;
  fetchFn: typeof fetch;
  clave: string;
  timeoutMs: number;
}

/** Un único envío a un modelo concreto. Nunca lanza. */
async function enviar(
  modelo: string,
  envio: Envio,
  conThinking: boolean,
): Promise<IntentoLLM> {
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), envio.timeoutMs);

  try {
    const respuesta = await envio.fetchFn(
      `https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": envio.clave,
        },
        signal: controlador.signal,
        body: JSON.stringify(cuerpoPeticion(envio.solicitud, conThinking)),
      },
    );

    if (!respuesta.ok) {
      const estado = await estadoGoogle(respuesta);
      return {
        texto: null,
        http: respuesta.status,
        motivo: `error_http:${respuesta.status}:${estado ?? "sin_estado"}`,
      };
    }

    const cuerpo = await respuesta.json();
    // Un finishReason distinto de "STOP" (MAX_TOKENS, SAFETY…) es un texto
    // cortado: se descarta aquí mismo y el llamador cae a su plantilla.
    const finDeRespuesta = extraerFinDeRespuesta(cuerpo);
    if (finDeRespuesta !== null && finDeRespuesta !== "STOP") {
      return {
        texto: null,
        http: respuesta.status,
        motivo: "validacion:truncado",
      };
    }
    return {
      texto: extraerTexto(cuerpo) ?? "",
      http: respuesta.status,
      motivo: "ok",
    };
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      return { texto: null, http: null, motivo: "timeout" };
    }
    return { texto: null, http: null, motivo: "error_red" };
  } finally {
    clearTimeout(temporizador);
  }
}

/**
 * Envío a un modelo. Si responde 400 (parámetro no reconocido, por ejemplo
 * thinkingConfig) se reintenta UNA vez sin él, para que la llamada no se rompa.
 */
async function enviarConReintentoDeParametro(
  modelo: string,
  envio: Envio,
): Promise<IntentoLLM> {
  const intento = await enviar(modelo, envio, true);
  if (intento.http === 400) {
    return await enviar(modelo, envio, false);
  }
  return intento;
}

/**
 * Pide a Gemini un texto y lo valida. Nunca lanza.
 *
 * Si el modelo principal responde 404 (retirado), 503 (no disponible) o 429
 * (cuota agotada) se hace UN único intento con el modelo de respaldo, sin
 * espera adicional. Ante 429 el motivo deja rastro de qué pasó:
 * gemini_429_principal_respaldo_ok (el respaldo redactó) o
 * gemini_429_ambos_plantilla (ninguno sirvió). Nunca se usa el respaldo ante
 * timeout. Si el respaldo tampoco sirve, el llamador cae a su plantilla.
 */
export async function generarConGemini(
  solicitud: SolicitudLLM,
  validador: ValidadorTexto,
  fetchFn: typeof fetch = fetch,
  opciones: OpcionesLLM = {},
): Promise<ResultadoLLM> {
  const principal = opciones.modelo ?? GEMINI_MODELO;
  const respaldo = opciones.modeloRespaldo ?? GEMINI_MODELO_RESPALDO;

  const clave = opciones.clave === undefined ? obtenerClave() : opciones.clave;
  if (!clave) return { texto: null, modelo: principal, motivo: "sin_clave" };

  const envio: Envio = {
    solicitud,
    fetchFn,
    clave,
    timeoutMs: opciones.timeoutMs ?? GEMINI_TIMEOUT_MS,
  };

  let modelo = principal;
  let intento = await enviarConReintentoDeParametro(modelo, envio);
  // El 429 (cuota agotada) también cae al respaldo, una sola vez y sin espera
  // adicional. Se recuerda para que el motivo final distinga si el respaldo
  // sirvió (gemini_429_principal_respaldo_ok) o si ninguno dio texto válido
  // (gemini_429_ambos_plantilla).
  const principalFue429 = intento.http === 429;

  if (intento.http === 404 || intento.http === 503 || principalFue429) {
    modelo = respaldo;
    intento = await enviarConReintentoDeParametro(modelo, envio);
  }

  if (intento.texto === null) {
    return {
      texto: null,
      modelo,
      motivo: principalFue429 ? "gemini_429_ambos_plantilla" : intento.motivo,
    };
  }

  const validacion = validador(intento.texto);
  if (!validacion.valido) {
    return {
      texto: null,
      modelo,
      motivo: principalFue429
        ? "gemini_429_ambos_plantilla"
        : `validacion:${validacion.motivo}`,
    };
  }
  return {
    texto: intento.texto,
    modelo,
    motivo: principalFue429 ? "gemini_429_principal_respaldo_ok" : "ok",
  };
}
