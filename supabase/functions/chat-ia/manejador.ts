// ============================================================================
// SmartMoney · Chat IA · Manejador HTTP (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/chat-ia
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body: { "mensaje": string }  (1 a 500 caracteres tras trim)
//
// El usuario_id SIEMPRE sale del JWT, nunca del body. Las lecturas y escrituras
// usan el cliente service_role filtrando por ese usuario_id.
//
// Flujo: valida el mensaje → aplica el límite diario → oculta datos personales
// → clasifica la intención → resuelve la respuesta → guarda los dos mensajes.
//
// La lógica vive aquí (y no en index.ts) para poder probarla sin servidor: las
// dependencias (usuario, datos, fetch y reloj) se pueden inyectar.
// ============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { limpiarMarkdownNoPermitido } from "../_shared/gemini.ts";
import {
  clasificarIntencion as clasificarIntencionReal,
  grupos as gruposReales,
  UMBRAL_INTENCION,
  type ClasificacionIntencion,
} from "./clasificadores.ts";
import { responderConsultaDatos } from "./consultar_datos.ts";
import { responderConversacion } from "./conversacion.ts";
import { RE_DECISION } from "./decision.ts";
import { responderFaq } from "./faq.ts";
import { responderAprendizaje } from "./aprender_concepto.ts";
import { responderConsejo } from "./pedir_consejo.ts";
import { hoyEnBogota, inicioDelDiaBogota, sumarDias } from "./fechas.ts";
import { minusculasSinTildes } from "./montos.ts";
import { ocultarDatosPersonales } from "./privacidad.ts";
import {
  crearRepositorioSupabase,
  type RepositorioChat,
} from "./repositorio.ts";
import { responderSimulacion } from "./simular_escenario.ts";
import type {
  Intencion,
  RespuestaChat,
  RespuestaIntencion,
} from "./tipos.ts";

/** Longitud máxima del mensaje del usuario (tras trim). */
export const LARGO_MAXIMO_MENSAJE = 500;

/** Mensajes del usuario permitidos por día (hora de Colombia). */
export const MAX_MENSAJES_POR_DIA = 40;

const CABECERAS_CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Todo lo externo que necesita el manejador, inyectable en las pruebas. */
export interface DependenciasChat {
  /** Resuelve el usuario a partir del JWT; null si el token no sirve. */
  resolverUsuario(jwt: string): Promise<string | null>;
  /** Acceso a datos (service_role) ya filtrable por usuario_id. */
  repositorio: RepositorioChat;
  /** fetch para Gemini. */
  fetchFn: typeof fetch;
  /** Reloj (para "hoy" y el límite diario). */
  ahora(): Date;
  /** Clave de Gemini; undefined = leer de GEMINI_API_KEY. */
  claveLLM?: string | null;
  /** Clasificador de intención. */
  clasificarIntencion(texto: string): ClasificacionIntencion;
}

// --- Utilidades HTTP ---------------------------------------------------------

function responder(cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CABECERAS_CORS, "Content-Type": "application/json" },
  });
}

function leerJwt(req: Request): string | null {
  const encabezado = req.headers.get("Authorization");
  if (!encabezado) return null;
  const [esquema, token] = encabezado.split(" ");
  if (!token || esquema.toLowerCase() !== "bearer") return null;
  return token;
}

async function leerCuerpo(req: Request): Promise<Record<string, unknown>> {
  const texto = await req.text();
  if (!texto) return {};
  try {
    const json = JSON.parse(texto);
    return typeof json === "object" && json !== null
      ? json as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function redondear(valor: number, decimales = 4): number {
  const factor = 10 ** decimales;
  return Math.round(valor * factor) / factor;
}

// --- Dependencias reales -----------------------------------------------------

function dependenciasReales(): DependenciasChat {
  const urlSupabase = Deno.env.get("SUPABASE_URL") ?? "";
  const claveAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const claveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const clienteUsuario = createClient(urlSupabase, claveAnon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin: SupabaseClient = createClient(urlSupabase, claveServicio, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return {
    resolverUsuario: async (jwt) => {
      const { data: { user }, error } = await clienteUsuario.auth.getUser(jwt);
      return error || !user ? null : user.id;
    },
    repositorio: crearRepositorioSupabase(admin),
    fetchFn: fetch,
    ahora: () => new Date(),
    clasificarIntencion: clasificarIntencionReal,
  };
}

/** Fábrica del respaldo. Las pruebas pueden sustituirla (ver más abajo). */
let fabricarDependenciasDeRespaldo: () => DependenciasChat = dependenciasReales;

/**
 * Solo para pruebas: sustituye la fábrica del respaldo para comprobar que el
 * manejador la usa cuando el segundo argumento no es un DependenciasChat.
 * Devuelve la fábrica anterior para poder restaurarla.
 */
export function fijarDependenciasDeRespaldo(
  fabrica: () => DependenciasChat,
): () => DependenciasChat {
  const anterior = fabricarDependenciasDeRespaldo;
  fabricarDependenciasDeRespaldo = fabrica;
  return anterior;
}

/**
 * Deno.serve invoca el manejador con (req, info): si el manejador se pasa
 * directamente, el ServeHandlerInfo ocupa el parámetro "deps" y el respaldo no
 * se aplicaría. Por eso no basta comprobar que venga algo: tiene que ser un
 * DependenciasChat de verdad.
 */
function esDependencias(valor: unknown): valor is DependenciasChat {
  if (typeof valor !== "object" || valor === null) return false;
  const posible = valor as Partial<DependenciasChat>;
  return typeof posible.resolverUsuario === "function" &&
    typeof posible.clasificarIntencion === "function" &&
    typeof posible.ahora === "function" &&
    typeof posible.fetchFn === "function" &&
    typeof posible.repositorio === "object" && posible.repositorio !== null;
}

// --- Reglas híbridas de intención --------------------------------------------

/** Una regla determinista: fija la intención sin consultar al modelo. */
interface ReglaIntencion {
  /** Nombre que queda en el motivo de auditoría (motivo = "regla:<nombre>"). */
  nombre: string;
  /** Intención que fija la regla. */
  intencion: Intencion;
  regex: RegExp;
}

/**
 * Condicionales explícitos que SIEMPRE son una simulación ("si recorto…",
 * "me alcanza para…") y que el modelo de n-gramas confunde con consultas o
 * consejos. Van PRIMERO: si el mensaje trae monto explícito y "cuanto" (por
 * ejemplo "cuanto me rinde"), gana la simulación. El motivo queda como
 * regla:<nombre> para poder separar en la evaluación lo que decide la regla de
 * lo que decide el modelo.
 */
const REGLAS_SIMULACION: ReglaIntencion[] = [
  {
    nombre: "si recorto",
    intencion: "simular_escenario",
    regex: /\bsi recorto\b/,
  },
  {
    nombre: "si reduzco",
    intencion: "simular_escenario",
    regex: /\bsi reduzco\b/,
  },
  {
    nombre: "si dejo de gastar",
    intencion: "simular_escenario",
    regex: /\bsi dejo de gastar\b/,
  },
  {
    nombre: "si dejo de pedir",
    intencion: "simular_escenario",
    regex: /\bsi dejo de pedir\b/,
  },
  { nombre: "si ahorro", intencion: "simular_escenario", regex: /\bsi ahorro\b/ },
  { nombre: "si guardo", intencion: "simular_escenario", regex: /\bsi guardo\b/ },
  {
    nombre: "me alcanza",
    intencion: "simular_escenario",
    regex: /\bme alcanza\b/,
  },
  {
    nombre: "puedo pagar",
    intencion: "simular_escenario",
    regex: /\bpuedo pagar\b/,
  },
  // "alcanzo a" / "llego a" solo cuentan si el objetivo es comprar, pagar o una meta.
  {
    nombre: "alcanzo a",
    intencion: "simular_escenario",
    regex: /\balcanzo a\b[^.!?,]{0,20}?\b(?:comprar|pagar|la meta)\b/,
  },
  {
    nombre: "llego a",
    intencion: "simular_escenario",
    regex: /\bllego a\b[^.!?,]{0,20}?\b(?:comprar|pagar|la meta)\b/,
  },
];

/**
 * Reglas nuevas, DESPUÉS de las de simulación y ANTES del modelo.
 * La decisión se mira primero que el concepto porque "que es mejor" es una
 * decisión y no una pregunta por un concepto.
 */
const REGLAS_CONCEPTO_Y_DECISION: ReglaIntencion[] = [
  {
    nombre: "decision",
    intencion: "pedir_consejo",
    regex: RE_DECISION,
  },
  {
    nombre: "concepto",
    intencion: "aprender_concepto",
    // Pregunta por un concepto y NO habla de la app: si menciona la app es una
    // pregunta de ayuda, y esa la decide el modelo.
    regex:
      /^(?=[\s\S]*\b(?:que es|q es|que son|que significa|que quiere decir|no entiendo|explicame|como funciona|para que sirve|diferencia entre)\b)(?![\s\S]*\b(?:app|aplicacion|smartmoney|asistente)\b)/,
  },
];

const REGLAS_INTENCION: ReglaIntencion[] = [
  ...REGLAS_SIMULACION,
  ...REGLAS_CONCEPTO_Y_DECISION,
];

/**
 * Regla que fija la intención, o null si ninguna aplica. El texto se normaliza
 * aquí (minúsculas y sin tildes).
 */
export function detectarReglaIntencion(
  mensaje: string,
): { nombre: string; intencion: Intencion } | null {
  const texto = minusculasSinTildes(mensaje);
  for (const regla of REGLAS_INTENCION) {
    if (regla.regex.test(texto)) {
      return { nombre: regla.nombre, intencion: regla.intencion };
    }
  }
  return null;
}

/** Cómo se eligió la intención: una regla, el modelo o el umbral. */
export type OrigenIntencion = "modelo" | "baja_confianza" | `regla:${string}`;

/** Resultado de decidir la intención de un mensaje. */
export interface DecisionIntencion {
  intencion: Intencion;
  confianza: number;
  origen: OrigenIntencion;
}

/**
 * Decide la intención del mensaje EXACTAMENTE como lo hace el manejador, en
 * este orden: reglas híbridas (deterministas) → modelo → umbral. Si ninguna
 * regla aplica y el modelo no da señal o su confianza no llega a
 * UMBRAL_INTENCION, responde con pedir_consejo. Es pura: no toca red ni
 * Supabase, y por eso se puede usar para evaluar el sistema fuera del servidor.
 */
export function decidirIntencion(
  mensaje: string,
  clasificar: (texto: string) => ClasificacionIntencion = clasificarIntencionReal,
): DecisionIntencion {
  const regla = detectarReglaIntencion(mensaje);
  if (regla !== null) {
    return {
      intencion: regla.intencion,
      confianza: 1,
      origen: `regla:${regla.nombre}`,
    };
  }

  const clasificacion = clasificar(mensaje);
  if (
    clasificacion.intencion === null ||
    clasificacion.confianza < UMBRAL_INTENCION
  ) {
    return {
      intencion: "pedir_consejo",
      confianza: clasificacion.confianza,
      origen: "baja_confianza",
    };
  }
  return {
    intencion: clasificacion.intencion,
    confianza: clasificacion.confianza,
    origen: "modelo",
  };
}

// --- Enrutamiento por intención ---------------------------------------------

async function resolverRespuesta(
  intencion: Intencion,
  mensaje: string,
  usuarioId: string,
  deps: DependenciasChat,
): Promise<RespuestaIntencion> {
  switch (intencion) {
    case "consultar_datos":
      return await responderConsultaDatos(
        mensaje,
        usuarioId,
        { repositorio: deps.repositorio, grupos: gruposReales },
        deps.ahora(),
      );
    case "ayuda_app":
      return responderFaq(mensaje);
    case "simular_escenario":
      return await responderSimulacion(mensaje, usuarioId, {
        repositorio: deps.repositorio,
        grupos: gruposReales,
        fetchFn: deps.fetchFn,
        claveLLM: deps.claveLLM,
      }, deps.ahora());
    case "conversacion":
      return await responderConversacion({
        mensaje,
        ultimoMensajeAsistente: await deps.repositorio.ultimoMensajeAsistente(
          usuarioId,
        ),
        fetchFn: deps.fetchFn,
        claveLLM: deps.claveLLM,
      });
    case "aprender_concepto":
      return await responderAprendizaje(mensaje, {
        repositorio: deps.repositorio,
        fetchFn: deps.fetchFn,
        claveLLM: deps.claveLLM,
      });
    case "pedir_consejo":
      return await responderConsejo(mensaje, usuarioId, {
        repositorio: deps.repositorio,
        grupos: gruposReales,
        fetchFn: deps.fetchFn,
        claveLLM: deps.claveLLM,
      }, deps.ahora());
    default:
      // Intención fuera del contrato: es un error de programación, no una
      // respuesta al usuario. El catch de manejarPeticion lo registra.
      throw new Error(`Intención desconocida: ${intencion}`);
  }
}

// --- HTTP --------------------------------------------------------------------

export async function manejarPeticion(
  req: Request,
  deps?: DependenciasChat,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CABECERAS_CORS });
  }

  try {
    if (req.method !== "POST") {
      return responder({ error: "Método no permitido." }, 405);
    }

    const jwt = leerJwt(req);
    if (!jwt) {
      return responder(
        { error: "Falta el encabezado Authorization con el JWT del usuario." },
        401,
      );
    }

    const dependencias = esDependencias(deps)
      ? deps
      : fabricarDependenciasDeRespaldo();
    const usuarioId = await dependencias.resolverUsuario(jwt);
    if (usuarioId === null) {
      return responder({ error: "Token inválido o vencido." }, 401);
    }

    const cuerpo = await leerCuerpo(req);
    const mensajeCrudo = cuerpo["mensaje"];
    if (typeof mensajeCrudo !== "string") {
      return responder({ error: "El campo 'mensaje' debe ser un texto." }, 400);
    }
    const mensaje = mensajeCrudo.trim();
    if (mensaje.length === 0) {
      return responder({ error: "Escríbeme algo y con gusto te ayudo." }, 400);
    }
    if (mensaje.length > LARGO_MAXIMO_MENSAJE) {
      return responder(
        {
          error:
            `Tu mensaje es muy largo. Resúmelo en ${LARGO_MAXIMO_MENSAJE} caracteres o menos.`,
        },
        400,
      );
    }

    const ahora = dependencias.ahora();
    const hoy = hoyEnBogota(ahora);
    const mensajesHoy = await dependencias.repositorio.contarMensajesUsuario(
      usuarioId,
      inicioDelDiaBogota(hoy),
      inicioDelDiaBogota(sumarDias(hoy, 1)),
    );
    if (mensajesHoy >= MAX_MENSAJES_POR_DIA) {
      return responder(
        {
          error:
            `Por hoy ya alcanzaste el límite de ${MAX_MENSAJES_POR_DIA} mensajes. Mañana seguimos revisando tus finanzas.`,
        },
        429,
      );
    }

    // A partir de aquí el mensaje ya está libre de datos personales.
    const limpio = ocultarDatosPersonales(mensaje);

    // Las reglas híbridas van ANTES del modelo: si una aplica, la intención y
    // la confianza no salen del clasificador. Toda esa decisión vive en
    // decidirIntencion (la misma que evalúa ia/fase6/evaluar_sistema.ts).
    const decision = decidirIntencion(limpio, dependencias.clasificarIntencion);
    const intencion = decision.intencion;
    const confianza = decision.confianza;

    const resultado = await resolverRespuesta(
      intencion,
      limpio,
      usuarioId,
      dependencias,
    );
    const confianzaFinal = redondear(confianza);
    // El motivo guarda DOS partes separadas por "|": cómo se eligió la
    // intención (regla, baja confianza o modelo) y qué pasó en el manejador
    // (por ejemplo si la respuesta salió de plantilla). Ejemplos:
    //   "regla:decision|consejo:validacion:cifra_no_permitida:1000000"
    //   "modelo|aprender:glosario:cdt"
    const motivo = `${decision.origen}|${resultado.motivo}`;

    // Última barrera antes de guardar y enviar: solo se admite el Markdown
    // permitido (**negrita**, viñetas "- " y saltos de línea). Nunca HTML.
    const respuestaFinal = limpiarMarkdownNoPermitido(resultado.respuesta);

    await dependencias.repositorio.insertarMensaje({
      usuario_id: usuarioId,
      rol: "usuario",
      contenido: limpio,
      intencion,
      confianza: confianzaFinal,
      origen: null,
      accion: null,
      motivo,
    });
    await dependencias.repositorio.insertarMensaje({
      usuario_id: usuarioId,
      rol: "asistente",
      contenido: respuestaFinal,
      intencion,
      confianza: confianzaFinal,
      origen: resultado.origen,
      accion: resultado.accion ?? null,
      motivo,
      aviso: resultado.aviso ?? null,
    });

    // Log de una línea, sin el contenido del mensaje.
    console.log(
      `[chat] intencion=${intencion} conf=${confianzaFinal} origen=${resultado.origen} motivo=${motivo}`,
    );

    const respuesta: RespuestaChat = {
      respuesta: respuestaFinal,
      intencion,
      confianza: confianzaFinal,
      origen: resultado.origen,
    };
    if (resultado.accion !== undefined) respuesta.accion = resultado.accion;
    if (resultado.aviso !== undefined) respuesta.aviso = resultado.aviso;
    return responder(respuesta);
  } catch (error) {
    // Mensaje genérico al cliente; el detalle queda solo en el log del servidor
    // (nunca el contenido del mensaje del usuario).
    console.error("chat-ia:", error);
    return responder(
      { error: "No pude procesar tu mensaje. Intenta de nuevo en un momento." },
      500,
    );
  }
}
