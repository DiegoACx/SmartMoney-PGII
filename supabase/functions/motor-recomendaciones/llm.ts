// ============================================================================
// SmartMoney · Motor de recomendaciones · Redacción con Gemini (LLM)
// ----------------------------------------------------------------------------
// Redacta el texto de UNA recomendación con Gemini y valida la salida antes de
// que el motor la guarde. Ante cualquier problema (sin clave, timeout, límite
// 429, error HTTP o texto no válido) devuelve null y el motor usa la plantilla.
//
// Privacidad (Ley 1581 de 2020): a Gemini solo se le envían el tipo, el nombre
// del grupo / categoría / meta o el título de la lección, y las cifras ya
// formateadas. NUNCA ids, usuario_id, correos, nombres de usuario ni
// descripciones de movimientos.
//
// La clave se lee de Deno.env ("GEMINI_API_KEY") y viaja en el header
// x-goog-api-key: nunca en la URL ni en los logs.
// ============================================================================

import {
  GEMINI_MODELO,
  GEMINI_MODELO_RESPALDO,
  GEMINI_TIMEOUT_MS,
  LLM_MAX_CARACTERES,
} from "./config.ts";
import { formatearCOP } from "./plantillas.ts";
import type { HallazgoPuntuado } from "./puntaje.ts";

/**
 * Motivo por el que la recomendación terminó saliendo (o no) del LLM:
 *   ok                              → texto de Gemini válido
 *   timeout                         → se agotó GEMINI_TIMEOUT_MS
 *   sin_clave                       → falta GEMINI_API_KEY
 *   error_http:<código>:<estado>    → respuesta HTTP con error (404:NOT_FOUND, 429:RESOURCE_EXHAUSTED…)
 *   error_red                       → no hubo respuesta HTTP (fallo de red o JSON ilegible)
 *   validacion:<motivo>             → llegó texto pero no pasó validarTextoLLM
 */
export type MotivoLLM =
  | "ok"
  | "timeout"
  | "sin_clave"
  | "error_red"
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
}

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

// --- Validación de la salida -------------------------------------------------

function recortarComillas(texto: string): string {
  const recortado = texto.trim();
  return recortado.replace(/^["'“”«»]+/, "").replace(/["'“”«»]+$/, "").trim();
}

/** Números presentes en un texto, sin $, % ni separador de miles. */
function extraerNumeros(texto: string): number[] {
  const limpio = texto.replace(/[$\s%]/g, " ");
  const coincidencias = limpio.match(/\d[\d.]*\d|\d/g) ?? [];
  return coincidencias.map((token) => Number(token.replace(/\./g, "")));
}

function numeroDeCifra(cifra: string): number {
  return extraerNumeros(cifra)[0] ?? Number.NaN;
}

/**
 * Rechaza el texto del LLM si está vacío, pasa de LLM_MAX_CARACTERES, trae una
 * URL o menciona algún número que no esté entre las cifras permitidas.
 */
export function validarTextoLLM(
  texto: string,
  cifrasPermitidas: string[],
): { valido: boolean; motivo: string } {
  const limpio = recortarComillas(texto ?? "");
  if (limpio.length === 0) return { valido: false, motivo: "vacio" };
  if (limpio.length > LLM_MAX_CARACTERES) return { valido: false, motivo: "largo" };
  if (/https?:\/\/|www\./i.test(limpio)) return { valido: false, motivo: "url" };

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

function extraerTexto(cuerpo: unknown): string | null {
  const candidatos = (cuerpo as { candidates?: unknown } | null)?.candidates;
  if (!Array.isArray(candidatos) || candidatos.length === 0) return null;
  const partes = (candidatos[0] as { content?: { parts?: unknown } } | null)
    ?.content?.parts;
  if (!Array.isArray(partes) || partes.length === 0) return null;
  const texto = (partes[0] as { text?: unknown } | null)?.text;
  return typeof texto === "string" ? texto : null;
}

/** `x-goog-api-key` va en el header: nunca en la URL ni en los logs. */
function cuerpoPeticion(
  hallazgo: HallazgoPuntuado,
  textoPlantilla: string,
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
    systemInstruction: { parts: [{ text: INSTRUCCION_SISTEMA }] },
    contents: [{
      role: "user",
      parts: [{ text: construirMensaje(hallazgo, textoPlantilla) }],
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
  hallazgo: HallazgoPuntuado;
  textoPlantilla: string;
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
        body: JSON.stringify(
          cuerpoPeticion(envio.hallazgo, envio.textoPlantilla, conThinking),
        ),
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
    return { texto: extraerTexto(cuerpo) ?? "", http: respuesta.status, motivo: "ok" };
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
 * Pide a Gemini el texto de la recomendación y lo valida. Nunca lanza.
 *
 * Si el modelo principal responde 404 (retirado) o 503 (no disponible) se hace
 * UN único intento con GEMINI_MODELO_RESPALDO. Nunca se usa el respaldo ante
 * timeout ni ante 429: no se alarga la espera ni se gasta cuota. Si el respaldo
 * tampoco sirve, el motor cae a la plantilla.
 */
export async function redactarConGemini(
  hallazgo: HallazgoPuntuado,
  textoPlantilla: string,
  fetchFn: typeof fetch = fetch,
  opciones: OpcionesLLM = {},
): Promise<ResultadoLLM> {
  const clave = opciones.clave === undefined ? obtenerClave() : opciones.clave;
  if (!clave) return { texto: null, modelo: GEMINI_MODELO, motivo: "sin_clave" };

  const envio: Envio = {
    hallazgo,
    textoPlantilla,
    fetchFn,
    clave,
    timeoutMs: opciones.timeoutMs ?? GEMINI_TIMEOUT_MS,
  };

  let modelo = GEMINI_MODELO;
  let intento = await enviarConReintentoDeParametro(modelo, envio);

  if (intento.http === 404 || intento.http === 503) {
    modelo = GEMINI_MODELO_RESPALDO;
    intento = await enviarConReintentoDeParametro(modelo, envio);
  }

  if (intento.texto === null) {
    return { texto: null, modelo, motivo: intento.motivo };
  }

  const validacion = validarTextoLLM(intento.texto, cifrasPermitidas(hallazgo));
  if (!validacion.valido) {
    return { texto: null, modelo, motivo: `validacion:${validacion.motivo}` };
  }
  return { texto: intento.texto, modelo, motivo: "ok" };
}
